require "rails_helper"

RSpec.describe WorkspacePolicy do
  it "allows all membership roles to view workspace and restricts update by role" do
    workspace = Workspace.create!(name: "Policy Workspace", slug: "policy-workspace")
    owner = User.create!(email: "policy-owner@example.com", password: "password123")
    admin = User.create!(email: "policy-admin@example.com", password: "password123")
    member = User.create!(email: "policy-member@example.com", password: "password123")
    guest = User.create!(email: "policy-guest@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: admin, role: :admin)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    expect(described_class.new(owner, workspace).show?).to be(true)
    expect(described_class.new(admin, workspace).show?).to be(true)
    expect(described_class.new(member, workspace).show?).to be(true)
    expect(described_class.new(guest, workspace).show?).to be(true)

    expect(described_class.new(owner, workspace).update?).to be(true)
    expect(described_class.new(admin, workspace).update?).to be(true)
    expect(described_class.new(member, workspace).update?).to be(false)
    expect(described_class.new(guest, workspace).update?).to be(false)
  end
end

RSpec.describe WorkspacePolicy::Scope do
  it "returns only workspaces the user belongs to" do
    user = User.create!(email: "scope@example.com", password: "password123")
    other_user = User.create!(email: "scope-other@example.com", password: "password123")
    visible_workspace = Workspace.create!(name: "Visible Workspace", slug: "visible-workspace")
    hidden_workspace = Workspace.create!(name: "Hidden Workspace", slug: "hidden-workspace")

    Membership.create!(user: user, workspace: visible_workspace, role: :owner)
    Membership.create!(user: other_user, workspace: hidden_workspace, role: :owner)

    resolved_scope = described_class.new(user, Workspace.all).resolve

    expect(resolved_scope).to contain_exactly(visible_workspace)
  end
end
