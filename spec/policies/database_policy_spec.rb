require "rails_helper"

RSpec.describe DatabasePolicy do
  it "allows owner/admin/member to create and blocks guest, auditor, and automation agent" do
    workspace = Workspace.create!(name: "DB Policy", slug: "db-policy")
    owner = User.create!(email: "db-owner@example.com", password: "password123")
    admin = User.create!(email: "db-admin@example.com", password: "password123")
    member = User.create!(email: "db-member@example.com", password: "password123")
    guest = User.create!(email: "db-guest@example.com", password: "password123")
    auditor = User.create!(email: "db-auditor@example.com", password: "password123")
    automation_agent = User.create!(email: "db-agent@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)
    Membership.create!(workspace: workspace, user: auditor, role: :auditor)
    Membership.create!(workspace: workspace, user: automation_agent, role: :automation_agent)

    database = Database.new(workspace: workspace, name: "Tasks")

    expect(described_class.new(owner, database).create?).to be(true)
    expect(described_class.new(admin, database).create?).to be(true)
    expect(described_class.new(member, database).create?).to be(true)
    expect(described_class.new(guest, database).create?).to be(false)
    expect(described_class.new(auditor, database).create?).to be(false)
    expect(described_class.new(automation_agent, database).create?).to be(false)
  end

  it "enforces private and specific user visibility modes" do
    workspace = Workspace.create!(name: "Database visibility policy", slug: "database-visibility-policy")
    owner = User.create!(email: "database-vis-owner@example.com", password: "password123")
    member = User.create!(email: "database-vis-member@example.com", password: "password123")
    other = User.create!(email: "database-vis-other@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: other, role: :member)

    private_database = Database.create!(
      workspace: workspace,
      created_by: owner,
      name: "Private grid",
      permission_mode: :private_database
    )
    specific_database = Database.create!(
      workspace: workspace,
      created_by: owner,
      name: "Specific grid",
      permission_mode: :specific_users
    )
    DatabaseShare.create!(database: specific_database, user: member, created_by: owner)

    expect(described_class.new(member, private_database).show?).to be(false)
    expect(described_class.new(owner, private_database).show?).to be(true)
    expect(described_class.new(member, specific_database).show?).to be(true)
    expect(described_class.new(other, specific_database).show?).to be(false)
  end

  it "scope returns only visible databases in accessible workspaces" do
    workspace = Workspace.create!(name: "Database scope policy", slug: "database-scope-policy")
    other_workspace = Workspace.create!(name: "Other database scope", slug: "other-database-scope")
    owner = User.create!(email: "database-scope-owner@example.com", password: "password123")
    member = User.create!(email: "database-scope-member@example.com", password: "password123")
    outsider = User.create!(email: "database-scope-outsider@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    shared_database = Database.create!(workspace: workspace, created_by: owner, name: "Shared grid", permission_mode: :shared_to_workspace)
    own_private_database = Database.create!(workspace: workspace, created_by: member, name: "Own private grid", permission_mode: :private_database)
    visible_specific_database = Database.create!(workspace: workspace, created_by: owner, name: "Visible specific grid", permission_mode: :specific_users)
    hidden_private_database = Database.create!(workspace: workspace, created_by: owner, name: "Hidden private grid", permission_mode: :private_database)
    hidden_specific_database = Database.create!(workspace: workspace, created_by: owner, name: "Hidden specific grid", permission_mode: :specific_users)
    outside_database = Database.create!(workspace: other_workspace, created_by: outsider, name: "Outside grid", permission_mode: :shared_to_workspace)

    DatabaseShare.create!(database: visible_specific_database, user: member, created_by: owner)

    resolved_ids = described_class::Scope.new(member, Database).resolve.pluck(:id)

    expect(resolved_ids).to contain_exactly(
      shared_database.id,
      own_private_database.id,
      visible_specific_database.id
    )
    expect(resolved_ids).not_to include(hidden_private_database.id, hidden_specific_database.id, outside_database.id)
  end
end
