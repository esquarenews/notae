require "rails_helper"

RSpec.describe Epistularium::DueSyncScheduler do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  def build_account(suffix:, provider: "imap", last_fresh_sync_at: nil, last_backfill_sync_at: nil, full_backfill_completed_at: nil)
    user = User.create!(email: "epistularium-due-sync-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Due Sync #{suffix}", slug: "epistularium-due-sync-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    settings = {}
    settings["last_fresh_sync_at"] = last_fresh_sync_at.iso8601 if last_fresh_sync_at.present?
    settings["last_backfill_sync_at"] = last_backfill_sync_at.iso8601 if last_backfill_sync_at.present?
    settings["full_backfill_completed_at"] = full_backfill_completed_at.iso8601 if full_backfill_completed_at.present?

    attributes = {
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: provider,
      label: "Inbox #{suffix}",
      enabled: true,
      status: "connected",
      settings_json: settings
    }

    if provider == "gmail"
      attributes[:access_token] = "gmail-token-#{suffix}"
    else
      attributes[:provider_username] = "me@example.com"
      attributes[:provider_password] = "secret"
      attributes[:settings_json] = settings.merge("imap_host" => "imap.example.com")
    end

    EpistulariumAccount.create!(attributes)
  end

  it "queues bootstrap syncs for accounts that have never performed a fresh sync" do
    account = build_account(suffix: "bootstrap", provider: "gmail")

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "bootstrap").on_queue("default")
  end

  it "queues incremental refresh every 10 minutes even while backfill is still pending" do
    account = build_account(
      suffix: "freshness-priority",
      provider: "gmail",
      last_fresh_sync_at: 11.minutes.ago,
      last_backfill_sync_at: 20.minutes.ago
    )
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-freshness-priority",
      mailbox: "inbox",
      subject: "Existing message",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental").on_queue("default")
  end

  it "queues lower-priority backfill once the hourly backfill window is due" do
    account = build_account(
      suffix: "backfill-due",
      provider: "imap",
      last_fresh_sync_at: 3.minutes.ago,
      last_backfill_sync_at: 61.minutes.ago
    )
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-backfill-due",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    expect do
      described_class.new(accounts: [ account ]).call
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "full_backfill").on_queue("epistularium_backfill")
  end

  it "skips accounts whose fresh check and backfill batch are both still current" do
    account = build_account(
      suffix: "fresh",
      provider: "imap",
      last_fresh_sync_at: 3.minutes.ago,
      last_backfill_sync_at: 20.minutes.ago
    )
    EpistulariumMessage.create!(
      workspace: account.workspace,
      epistularium_account: account,
      provider_message_id: "msg-fresh",
      mailbox: "inbox",
      subject: "Existing message",
      from_email: "alex@example.com",
      body_text: "Existing body"
    )

    expect do
      described_class.new(accounts: [ account ]).call
    end.not_to have_enqueued_job(Epistularium::SyncConnectionJob)
  end

  it "does not enqueue a duplicate sync while the account is already queued" do
    account = build_account(
      suffix: "already-queued",
      last_fresh_sync_at: 11.minutes.ago
    )
    account.mark_sync_enqueued!(at: 1.minute.ago)

    expect do
      described_class.new(accounts: [ account ]).call
    end.not_to have_enqueued_job(Epistularium::SyncConnectionJob)
  end

  it "recovers stale sync state and re-queues the overdue fresh sync" do
    account = build_account(
      suffix: "stale-lock",
      last_fresh_sync_at: 11.minutes.ago
    )
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
    end.to have_enqueued_job(Epistularium::SyncConnectionJob).with(account.id, mode: "incremental").on_queue("default")

    expect(account.reload.sync_started_at).to be_nil
  end
end
