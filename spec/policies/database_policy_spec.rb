require "rails_helper"

RSpec.describe DatabasePolicy do
  it "allows owner/admin/member to create and blocks guests" do
    workspace = Workspace.create!(name: "DB Policy", slug: "db-policy")
    owner = User.create!(email: "db-owner@example.com", password: "password123")
    admin = User.create!(email: "db-admin@example.com", password: "password123")
    member = User.create!(email: "db-member@example.com", password: "password123")
    guest = User.create!(email: "db-guest@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    database = Database.new(workspace: workspace, name: "Tasks")

    expect(described_class.new(owner, database).create?).to be(true)
    expect(described_class.new(admin, database).create?).to be(true)
    expect(described_class.new(member, database).create?).to be(true)
    expect(described_class.new(guest, database).create?).to be(false)
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
end
