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
end
