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
end
