require "rails_helper"

RSpec.describe EpistulariumAccount, type: :model do
  def build_workspace_stack(suffix:)
    user = User.create!(email: "epistularium-account-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Account #{suffix}", slug: "epistularium-account-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    [ user, workspace ]
  end

  it "requires Gmail OAuth tokens for Gmail accounts" do
    user, workspace = build_workspace_stack(suffix: "gmail-validation")
    account = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Inbox"
    )

    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("access token or refresh token")
  end

  it "requires IMAP connection details for IMAP-backed accounts" do
    user, workspace = build_workspace_stack(suffix: "imap-validation")
    account = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox"
    )

    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("Provider username")
    expect(account.errors.full_messages.join).to include("Provider password")
    expect(account.errors.full_messages.join).to include("IMAP host")
  end

  it "defaults Amazon WorkMail sent mailbox names when none is configured" do
    user, workspace = build_workspace_stack(suffix: "workmail-defaults")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "amazon_workmail",
      label: "WorkMail",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.mail.example.com" }
    )

    expect(account.sent_mailbox_name).to eq("Sent Items")
    expect(account.imap_ssl?).to eq(true)
  end

  it "normalizes mailbox colour codes and rejects invalid values" do
    user, workspace = build_workspace_stack(suffix: "colour")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com", "account_color" => " #F97316 " }
    )

    expect(account.reload.account_color).to eq("#f97316")

    account.settings_json = account.settings_json.to_h.merge("account_color" => "orange")
    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("Mailbox colour must be a hex colour code")
  end

  it "rejects SMTP endpoints for IMAP-backed accounts with a clearer validation error" do
    user, workspace = build_workspace_stack(suffix: "smtp-host-validation")
    account = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "amazon_workmail",
      label: "WorkMail",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "smtp.eu-west-1.mail.awsapps.com" }
    )

    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("Use the Amazon WorkMail IMAP endpoint")
  end

  it "rejects IMAP hosts targeting local or private networks" do
    user, workspace = build_workspace_stack(suffix: "imap-private-host")
    account = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "192.168.1.10" }
    )

    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("IMAP host must use a public host.")
  end

  it "requires Amazon WorkMail usernames to be full email addresses" do
    user, workspace = build_workspace_stack(suffix: "workmail-username-validation")
    account = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "amazon_workmail",
      label: "WorkMail",
      provider_username: "Errol",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.mail.eu-west-1.awsapps.com" }
    )

    expect(account).not_to be_valid
    expect(account.errors.full_messages.join).to include("full email address")
  end

  it "tracks persistent sync state in settings_json for cross-process recovery" do
    user, workspace = build_workspace_stack(suffix: "sync-state")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )

    account.mark_sync_enqueued!(at: 5.minutes.ago)
    account.mark_sync_started!(at: 10.minutes.ago)
    account.reload

    expect(account.sync_recently_enqueued?(within: 10.minutes)).to eq(true)
    expect(account.sync_active?(stale_after: 20.minutes)).to eq(true)

    account.mark_sync_started!(at: 25.minutes.ago)

    expect(account.reload.stale_sync?(stale_after: 20.minutes)).to eq(true)
    expect(account.clear_stale_sync_state!(stale_after: 20.minutes)).to eq(true)

    expect(account.reload.sync_started_at).to be_nil
    expect(account.sync_enqueued_at).to be_present
  end

  it "reads freshness and backfill timestamps from settings_json and evaluates due windows separately" do
    user, workspace = build_workspace_stack(suffix: "sync-timestamps")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Gmail",
      access_token: "gmail-token",
      settings_json: {
        "last_fresh_sync_at" => 11.minutes.ago.iso8601,
        "last_backfill_sync_at" => 61.minutes.ago.iso8601
      }
    )

    expect(account.last_fresh_sync_at).to be_within(1.second).of(11.minutes.ago)
    expect(account.last_backfill_sync_at).to be_within(1.second).of(61.minutes.ago)
    expect(account.fresh_sync_due?).to eq(true)
    expect(account.backfill_sync_due?).to eq(true)

    account.update!(
      settings_json: account.settings_json.to_h.merge(
        "last_fresh_sync_at" => 3.minutes.ago.iso8601,
        "last_backfill_sync_at" => 20.minutes.ago.iso8601
      )
    )

    expect(account.reload.fresh_sync_due?).to eq(false)
    expect(account.backfill_sync_due?).to eq(false)
  end

  it "falls back to last_synced_at for legacy freshness checks until the dedicated marker is populated" do
    user, workspace = build_workspace_stack(suffix: "legacy-freshness")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      last_synced_at: 15.minutes.ago,
      settings_json: { "imap_host" => "imap.example.com" }
    )

    expect(account.last_fresh_sync_at).to be_within(1.second).of(15.minutes.ago)
    expect(account.fresh_sync_due?).to eq(true)
  end

  it "treats Gmail and IMAP accounts as pending full backfill until completion is recorded" do
    user, workspace = build_workspace_stack(suffix: "backfill-pending")
    gmail_account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Gmail",
      access_token: "gmail-token",
      settings_json: {}
    )
    imap_account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "IMAP",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )

    expect(gmail_account.full_backfill_pending?).to eq(true)
    expect(imap_account.full_backfill_pending?).to eq(true)

    gmail_account.update!(settings_json: { "full_backfill_completed_at" => Time.current.iso8601 })
    imap_account.update!(settings_json: { "imap_host" => "imap.example.com", "full_backfill_completed_at" => Time.current.iso8601 })

    expect(gmail_account.reload.full_backfill_pending?).to eq(false)
    expect(imap_account.reload.full_backfill_pending?).to eq(false)
  end

  it "surfaces the freshest mailbox activity when imported messages are newer than the account sync timestamp" do
    user, workspace = build_workspace_stack(suffix: "visible-sync")
    account = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" },
      last_synced_at: 7.hours.ago
    )
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-visible-sync",
      mailbox: "inbox",
      subject: "Visible sync",
      from_email: "sender@example.com",
      body_text: "Mailbox activity should win."
    )
    message.update!(last_synced_at: 30.minutes.ago)

    expect(account.last_visible_sync_at).to be_within(1.second).of(30.minutes.ago)

    account.update!(last_synced_at: 5.minutes.ago)

    expect(account.last_visible_sync_at).to be_within(1.second).of(5.minutes.ago)
  end
end
