require "rails_helper"

RSpec.describe Epistularium::SyncConnectionJob, type: :job do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def build_account(suffix:, provider: "imap", settings_json: {})
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
      status: "connected",
      settings_json: settings_json
    }

    if provider == "gmail"
      attributes[:access_token] = "google-token-#{suffix}"
    else
      attributes[:provider_username] = "me@example.com"
      attributes[:provider_password] = "secret"
      attributes[:settings_json] = { "imap_host" => "imap.example.com" }.merge(settings_json)
    end

    EpistulariumAccount.create!(attributes)
  end

  it "auto-disables the account on permanent authentication failures" do
    account = build_account(suffix: "auth-failure")
    sync_service = instance_double(Epistularium::ConnectionSyncService)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)
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
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)
    allow(sync_service).to receive(:call).and_raise(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect do
      described_class.perform_now(account.id)
    end.to raise_error(RuntimeError, "Net::ReadTimeout while contacting provider")

    expect(account.reload.enabled).to be(true)
  end

  it "queues the bootstrap backfill kickoff onto the low-priority backfill queue for IMAP accounts" do
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
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill").on_queue("epistularium_backfill")

    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(1)
  end

  it "bootstraps Gmail with a small incremental sync before queueing low-priority backfill" do
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
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill").on_queue("epistularium_backfill")
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
    account = build_account(suffix: "incremental", settings_json: { "last_fresh_sync_at" => 2.hours.ago.iso8601 })
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

  it "queues a knowledge suggestion refresh after a successful sync" do
    account = build_account(suffix: "knowledge-refresh")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    expect do
      described_class.perform_now(account.id)
    end.to have_enqueued_job(Search::QueueKnowledgeSuggestionRefreshJob).with(account.workspace_id).on_queue("default")
  end

  it "kicks off backfill after a fresh incremental run only when the backfill window is due" do
    account = build_account(
      suffix: "incremental-backfill-follow-up",
      provider: "gmail",
      settings_json: {
        "last_fresh_sync_at" => 11.minutes.ago.iso8601,
        "last_backfill_sync_at" => 61.minutes.ago.iso8601
      }
    )
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-incremental-backfill-follow-up",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: true)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    expect do
      described_class.perform_now(account.id, mode: "incremental")
    end.to have_enqueued_job(described_class).with(account.id, mode: "full_backfill").on_queue("epistularium_backfill")
  end

  it "does not immediately queue another backfill after incremental when the hourly backfill window is not due" do
    account = build_account(
      suffix: "incremental-no-backfill-follow-up",
      provider: "gmail",
      settings_json: {
        "last_fresh_sync_at" => 11.minutes.ago.iso8601,
        "last_backfill_sync_at" => 20.minutes.ago.iso8601
      }
    )
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-incremental-no-backfill-follow-up",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )
    clear_enqueued_jobs
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: true)
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: false,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id, mode: "incremental")

    follow_up_jobs = enqueued_jobs.select { |job| job[:job] == described_class }
    expect(follow_up_jobs).to be_empty
  end

  it "does not immediately chain another full backfill batch when more IMAP history remains" do
    account = build_account(suffix: "follow-up")
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: true })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id, mode: "full_backfill")

    follow_up_jobs = enqueued_jobs.select { |job| job[:job] == described_class }
    expect(follow_up_jobs).to be_empty
  end

  it "clears stale sync state before claiming a new run" do
    account = build_account(suffix: "stale-state")
    account.mark_sync_started!(at: 30.minutes.ago)
    sync_service = instance_double(Epistularium::ConnectionSyncService, call: { backfill_remaining: false })
    allow(Epistularium::ConnectionSyncService).to receive(:new).with(
      account: account,
      full_backfill: true,
      max_messages_per_mailbox: 50,
      update_cursor: true
    ).and_return(sync_service)

    described_class.perform_now(account.id)

    expect(account.reload.sync_started_at).to be_nil
    expect(sync_service).to have_received(:call)
  end
end
