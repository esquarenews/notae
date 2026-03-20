require "rails_helper"

RSpec.describe EpistulariumAccountPolicy do
  it "allows owners to view personal accounts and blocks other members" do
    workspace = Workspace.create!(name: "Epistularium Policy", slug: "epistularium-policy")
    owner = User.create!(email: "epistularium-policy-owner@example.com", password: "password123")
    member = User.create!(email: "epistularium-policy-member@example.com", password: "password123")

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

    expect(described_class.new(owner, account).show?).to be(true)
    expect(described_class.new(member, account).show?).to be(false)
  end

  it "allows workspace members to view shared accounts but only admins or owners to update them" do
    workspace = Workspace.create!(name: "Epistularium Shared Policy", slug: "epistularium-shared-policy")
    owner = User.create!(email: "epistularium-shared-owner@example.com", password: "password123")
    admin = User.create!(email: "epistularium-shared-admin@example.com", password: "password123")
    member = User.create!(email: "epistularium-shared-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
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

    expect(described_class.new(member, account).show?).to be(true)
    expect(described_class.new(member, account).update?).to be(false)
    expect(described_class.new(admin, account).update?).to be(true)
    expect(described_class.new(owner, account).update?).to be(true)
  end
end
