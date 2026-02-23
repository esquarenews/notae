require "rails_helper"

RSpec.describe Membership, type: :model do
  it "enforces one membership per user per workspace" do
    user = User.create!(email: "unique@example.com", password: "password123")
    workspace = Workspace.create!(name: "Workspace", slug: "workspace")
    described_class.create!(user: user, workspace: workspace, role: :owner)
    duplicate = described_class.new(user: user, workspace: workspace, role: :member)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("has already been taken")
  end

  it "defaults role to member" do
    user = User.create!(email: "role@example.com", password: "password123")
    workspace = Workspace.create!(name: "Role Workspace", slug: "role-workspace")
    membership = described_class.create!(user: user, workspace: workspace)

    expect(membership.role).to eq("member")
  end

  it "stores guest role explicitly" do
    user = User.create!(email: "guest-role@example.com", password: "password123")
    workspace = Workspace.create!(name: "Guest Workspace", slug: "guest-workspace")
    membership = described_class.create!(user: user, workspace: workspace, role: :guest)

    expect(membership).to be_guest
  end
end
