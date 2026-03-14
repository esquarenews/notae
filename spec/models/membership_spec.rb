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

  it "treats auditors as read-only and automation agents as draft authors" do
    workspace = Workspace.create!(name: "Extended Roles", slug: "extended-roles")
    auditor_user = User.create!(email: "auditor-role@example.com", password: "password123")
    agent_user = User.create!(email: "automation-agent-role@example.com", password: "password123")

    auditor = described_class.create!(user: auditor_user, workspace: workspace, role: :auditor)
    automation_agent = described_class.create!(user: agent_user, workspace: workspace, role: :automation_agent)

    expect(auditor).to be_auditor
    expect(auditor.read_only?).to eq(true)
    expect(auditor.audit_reviewer?).to eq(true)
    expect(auditor.can_author_agent_actions?).to eq(false)

    expect(automation_agent).to be_automation_agent
    expect(automation_agent.read_only?).to eq(false)
    expect(automation_agent.content_editor?).to eq(false)
    expect(automation_agent.can_author_agent_actions?).to eq(true)
  end
end
