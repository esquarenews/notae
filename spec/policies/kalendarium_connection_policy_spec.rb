require "rails_helper"

RSpec.describe KalendariumConnectionPolicy do
  it "allows shared connections for members but restricts updates to admin/owner" do
    workspace = Workspace.create!(name: "Kal Policy Shared", slug: "kal-policy-shared")
    owner = User.create!(email: "kal-pol-owner@example.com", password: "password123")
    admin = User.create!(email: "kal-pol-admin@example.com", password: "password123")
    member = User.create!(email: "kal-pol-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: owner,
      provider: "google",
      label: "Workspace Calendar",
      access_token: "token"
    )

    expect(described_class.new(member, connection).show?).to be(true)
    expect(described_class.new(member, connection).update?).to be(false)
    expect(described_class.new(admin, connection).update?).to be(true)
    expect(described_class.new(owner, connection).update?).to be(true)
  end

  it "limits personal connections to their owner" do
    workspace = Workspace.create!(name: "Kal Policy Personal", slug: "kal-policy-personal")
    owner = User.create!(email: "kal-pol-personal-owner@example.com", password: "password123")
    member = User.create!(email: "kal-pol-personal-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "icloud_caldav",
      label: "Owner iCloud",
      provider_username: "owner@example.com",
      provider_password: "secret"
    )

    expect(described_class.new(owner, connection).show?).to be(true)
    expect(described_class.new(owner, connection).update?).to be(true)
    expect(described_class.new(member, connection).show?).to be(false)
    expect(described_class.new(member, connection).update?).to be(false)
  end

  it "scopes to shared plus current-user personal connections" do
    workspace = Workspace.create!(name: "Kal Policy Scope", slug: "kal-policy-scope")
    member = User.create!(email: "kal-pol-scope-member@example.com", password: "password123")
    other_user = User.create!(email: "kal-pol-scope-other@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: other_user, role: :member)

    shared = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: member,
      provider: "ics",
      label: "Shared feed",
      ics_url: "https://example.com/feed.ics"
    )
    own_personal = KalendariumConnection.create!(
      workspace: workspace,
      owner: member,
      created_by: member,
      provider: "google",
      label: "My Google",
      access_token: "mine"
    )
    other_personal = KalendariumConnection.create!(
      workspace: workspace,
      owner: other_user,
      created_by: other_user,
      provider: "google",
      label: "Other Google",
      access_token: "other"
    )

    scoped_ids = described_class::Scope.new(member, KalendariumConnection).resolve.pluck(:id)

    expect(scoped_ids).to include(shared.id, own_personal.id)
    expect(scoped_ids).not_to include(other_personal.id)
  end
end
