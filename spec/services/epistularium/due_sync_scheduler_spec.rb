require "rails_helper"

RSpec.describe Epistularium::DueSyncScheduler do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def build_account(suffix:, provider: "imap", last_synced_at: nil)
    user = User.create!(email: "epistularium-due-sync-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Due Sync #{suffix}", slug: "epistularium-due-sync-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    attributes = {
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: provider,
      label: "Inbox #{suffix}",
      enabled: true,
      status: "connected",
      last_synced_at: last_synced_at
    }

    if provider == "gmail"
      attributes[:access_token] = "gmail-token-#{suffix}"
    else
      attributes[:provider_username] = "me@example.com"
      attributes[:provider_password] = "secret"
      attributes[:settings_json] = { "imap_host" => "imap.example.com" }
    end

    EpistulariumAccount.create!(attributes)
  end

  it "queues bootstrap syncs for never-synced accounts" do
    account = build_account(suffix: "bootstrap", provider: "gmail", last_synced_at: nil)

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "bootstrap")
  end

  it "queues normal due syncs for stale accounts that have already synced" do
    account = build_account(suffix: "stale", last_synced_at: 11.minutes.ago)
    account.update!(settings_json: account.settings_json.to_h.merge("full_backfill_completed_at" => Time.current.iso8601))
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-stale",
      mailbox: "inbox",
      subject: "Existing message",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id)
  end

  it "queues incremental refresh for stale accounts whose history is still incomplete" do
    account = build_account(suffix: "stale-backfill", provider: "gmail", last_synced_at: 11.minutes.ago)
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-stale-backfill",
      mailbox: "inbox",
      subject: "Existing message",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental")
  end

  it "skips recently synced accounts" do
    account = build_account(suffix: "fresh", last_synced_at: 3.minutes.ago)

    expect do
      described_class.new(accounts: [ account ]).call
    end.not_to have_enqueued_job(Epistularium::SyncConnectionJob)
  end

  it "does not enqueue a duplicate sync while the account is actively syncing" do
    account = build_account(suffix: "active", last_synced_at: 11.minutes.ago)
    account.mark_sync_started!(at: 2.minutes.ago)

    expect do
      described_class.new(accounts: [ account ]).call
    end.not_to have_enqueued_job(Epistularium::SyncConnectionJob)
  end

  it "recovers stale sync state and queues the overdue sync again" do
    account = build_account(suffix: "stale-lock", last_synced_at: 11.minutes.ago)
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-stale-lock",
      mailbox: "inbox",
      subject: "Existing message",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )
    account.mark_sync_started!(at: 25.minutes.ago)

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental")

    expect(account.reload.sync_started_at).to be_nil
  end
end
