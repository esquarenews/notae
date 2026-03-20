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
end
