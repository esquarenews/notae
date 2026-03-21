require "rails_helper"

RSpec.describe Epistularium::SyncConnectionJob, type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def build_account(suffix:, provider: "imap")
    user = User.create!(email: "epistularium-sync-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Sync Job #{suffix}", slug: "epistularium-sync-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    attributes = {
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: provider,
      label: "Inbox #{suffix}",
      enabled: true,
      status: "connected"
    }

    if provider == "gmail"
      attributes[:access_token] = "google-token-#{suffix}"
    else
      attributes[:provider_username] = "me@example.com"
      attributes[:provider_password] = "secret"
      attributes[:settings_json] = { "imap_host" => "imap.example.com" }
    end

    EpistulariumAccount.create!(attributes)
  end

  it "auto-disables the account on permanent authentication failures" do
    account = build_account(suffix: "auth-failure")
    sync_service = instance_double(Epistularium::ConnectionSyncService)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(account: account, full_backfill: true, max_messages_per_mailbox: 200, update_cursor: true).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "IMAP authentication failed: Invalid credentials")

    expect do
      described_class.perform_now(account.id)
    end.not_to raise_error

    account.reload
    expect(account.enabled).to be(false)
    expect(account.status).to eq("sync_error")
    expect(account.last_error).to include("Auto-disabled after authentication failure")
  end

  it "re-raises transient failures so normal retries still apply" do
    account = build_account(suffix: "transient")
    sync_service = instance_double(Epistularium::ConnectionSyncService)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(account: account, full_backfill: true, max_messages_per_mailbox: 200, update_cursor: true).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect do
      described_class.perform_now(account.id)
    end.to raise_error(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect(account.reload.enabled).to be(true)
  end

  it "queues a follow-up full backfill after the bootstrap sync for IMAP-backed accounts" do
    account = build_account(suffix: "bootstrap")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: false
    ).and_return(sync_service)

    expect do
      described_class.perform_now(account.id, mode: "bootstrap")
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill")

    queued_runs = enqueued_jobs.select { |job| job[:job] == described_class && job[:args].first == account.id }
    expect(queued_runs.map { |job| job[:at].present? }).to include(true)
  end

  it "bootstraps Gmail with a small incremental sync before queueing full backfill" do
    account = build_account(suffix: "gmail-bootstrap", provider: "gmail")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: true)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    expect do
      described_class.perform_now(account.id, mode: "bootstrap")
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill")
  end

  it "runs Gmail full backfill without truncating mailbox history to the IMAP batch size" do
    account = build_account(suffix: "gmail-full", provider: "gmail")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: true)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id, mode: "full_backfill")

    expect(sync_service).to have_received(:call)
  end

  it "runs a bounded incremental sync for stalled-queue recovery" do
    account = build_account(suffix: "incremental")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id, mode: "incremental")

    expect(sync_service).to have_received(:call)
  end

  it "re-enqueues bounded full backfill work when more IMAP history remains" do
    account = build_account(suffix: "follow-up")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: true })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 200,
      update_cursor: true
    ).and_return(sync_service)

    expect do
      described_class.perform_now(account.id, mode: "full_backfill")
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill")
  end

  it "queues a recurring follow-up sync 10 minutes after a successful run" do
    account = build_account(suffix: "recurring")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 200,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id)

    recurring_job = enqueued_jobs.find do |job|
      job[:job] == described_class &&
        job[:at].present?
    end

    expect(recurring_job).to be_present
    expect(recurring_job[:at]).to be_within(5.seconds).of(10.minutes.from_now.to_f)
  end

  it "queues the next recurring sync after consuming the queued marker for the current run" do
    account = build_account(suffix: "recurring-from-enqueue")
    original_enqueued_at = 30.seconds.ago
    account.mark_sync_enqueued!(at: original_enqueued_at)
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 200,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id)

    recurring_job = enqueued_jobs.find do |job|
      job[:job] == described_class &&
        job[:args].first == account.id &&
        job[:at].present?
    end

    expect(recurring_job).to be_present
    expect(account.reload.sync_enqueued_at).to be > original_enqueued_at
  end

  it "queues recurring full backfill polling when mailbox history is still incomplete" do
    account = build_account(suffix: "recurring-incomplete-backfill", provider: "gmail")
    sync_service = instance_double(Epistularium::ConnectionSyncService)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)
    allow(sync_service).to receive(:call) do
      EpistulariumMessage.create!(
        workspace: account.workspace,
        epistularium_account: account,
        provider_message_id: "msg-recurring-incomplete-backfill",
        mailbox: "inbox",
        subject: "Recent message",
        from_email: "alex@example.com",
        body_text: "Recent body"
      )
      account.update!(last_synced_at: Time.current)
      true
    end

    described_class.perform_now(account.id, mode: "bootstrap")

    expect(enqueued_jobs).to include(
      a_hash_including(
        job: described_class,
        at: kind_of(Numeric),
        args: [ account.id, a_hash_including("mode" => "full_backfill") ]
      )
    )
  end

  it "clears stale sync state before claiming a new run" do
    account = build_account(suffix: "stale-state")
    account.mark_sync_started!(at: 30.minutes.ago)
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 200,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id)

    expect(account.reload.sync_started_at).to be_nil
    expect(sync_service).to have_received(:call)
  end
end
