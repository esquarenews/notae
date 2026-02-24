require "rails_helper"

RSpec.describe DatabaseViewPolicy do
  it "allows owners/admins/members to manage views and blocks guests" do
    workspace = Workspace.create!(name: "View policy workspace", slug: "view-policy-workspace")
    database = Database.create!(workspace: workspace, name: "Tasks")
    owner = User.create!(email: "view-policy-owner@example.com", password: "password123")
    member = User.create!(email: "view-policy-member@example.com", password: "password123")
    guest = User.create!(email: "view-policy-guest@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)
    view = DatabaseView.new(workspace: workspace, database: database, created_by: owner, name: "Table")

    expect(described_class.new(owner, view).create?).to eq(true)
    expect(described_class.new(member, view).create?).to eq(true)
    expect(described_class.new(guest, view).create?).to eq(false)
  end
end
