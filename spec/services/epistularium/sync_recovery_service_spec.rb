require "rails_helper"

RSpec.describe Epistularium::SyncRecoveryService do
  def build_account(suffix:, provider: "imap", last_synced_at: nil, with_message: false)
    user = User.create!(email: "epistularium-sync-recovery-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium Sync Recovery #{suffix}", slug: "epistularium-sync-recovery-#{suffix}")
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

    account = EpistulariumAccount.create!(attributes)
    if with_message
      EpistulariumMessage.create!(
        workspace: workspace,
        epistularium_account: account,
        provider_message_id: "msg-#{suffix}",
        mailbox: "inbox",
        subject: "Existing message",
        from_name: "Alex",
        from_email: "alex@example.com",
        body_text: "Existing body"
      )
    end

    account
  end

  it "recovers a stalled bootstrap Gmail sync inline" do
    account = build_account(suffix: "gmail-bootstrap", provider: "gmail", last_synced_at: nil, with_message: false)
    account.mark_sync_enqueued!(at: 3.minutes.ago)

    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    expect(described_class.new(account: account).call).to eq(true)
    expect(Epistularium::SyncConnectionJob).to have_received(:perform_now).with(account.id, mode: "bootstrap")
  end

  it "recovers a stalled stale-account sync with a bounded incremental run" do
    account = build_account(suffix: "imap-incremental", last_synced_at: 30.minutes.ago, with_message: true)
    account.mark_sync_enqueued!(at: 3.minutes.ago)

    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    expect(described_class.new(account: account).call).to eq(true)
    expect(Epistularium::SyncConnectionJob).to have_received(:perform_now).with(account.id, mode: "incremental")
  end

  it "skips recovery when the queued sync is still fresh" do
    account = build_account(suffix: "fresh-queue", last_synced_at: nil)
    account.mark_sync_enqueued!(at: 30.seconds.ago)

    allow(Epistularium::SyncConnectionJob).to receive(:perform_now)

    expect(described_class.new(account: account).call).to eq(false)
    expect(Epistularium::SyncConnectionJob).not_to have_received(:perform_now)
  end
end
