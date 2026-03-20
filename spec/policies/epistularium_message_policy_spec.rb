require "rails_helper"

RSpec.describe EpistulariumMessagePolicy do
  it "allows the message owner to view and suggest drafts from a personal email" do
    workspace = Workspace.create!(name: "Epistularium Message Policy", slug: "epistularium-message-policy")
    owner = User.create!(email: "epistularium-message-owner@example.com", password: "password123")
    member = User.create!(email: "epistularium-message-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "imap",
      label: "Private inbox",
      provider_username: "owner@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-policy-private",
      subject: "Private note",
      from_email: "alex@example.com",
      body_text: "Private message body"
    )

    expect(described_class.new(owner, message).show?).to be(true)
    expect(described_class.new(owner, message).suggest?).to be(true)
    expect(described_class.new(member, message).show?).to be(false)
    expect(described_class.new(member, message).suggest?).to be(false)
  end

  it "allows workspace members to view and suggest drafts from shared email accounts" do
    workspace = Workspace.create!(name: "Epistularium Shared Message Policy", slug: "epistularium-shared-message-policy")
    owner = User.create!(email: "epistularium-shared-message-owner@example.com", password: "password123")
    member = User.create!(email: "epistularium-shared-message-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: workspace,
      created_by: owner,
      provider: "imap",
      label: "Shared inbox",
      provider_username: "shared@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-policy-shared",
      subject: "Shared note",
      from_email: "alex@example.com",
      body_text: "Shared message body"
    )

    expect(described_class.new(member, message).show?).to be(true)
    expect(described_class.new(member, message).suggest?).to be(true)
  end
end
