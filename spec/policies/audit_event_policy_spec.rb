require "rails_helper"

RSpec.describe AuditEventPolicy::Scope do
  it "returns audit events only for admin/owner memberships" do
    owner = User.create!(email: "audit-owner@example.com", password: "password123")
    member = User.create!(email: "audit-member@example.com", password: "password123")
    owner_workspace = Workspace.create!(name: "Owner Audit", slug: "owner-audit")
    member_workspace = Workspace.create!(name: "Member Audit", slug: "member-audit")
    Membership.create!(workspace: owner_workspace, user: owner, role: :owner)
    Membership.create!(workspace: member_workspace, user: owner, role: :member)
    Membership.create!(workspace: member_workspace, user: member, role: :owner)
    owner_event = AuditEvent.create!(workspace: owner_workspace, actor: owner, action: "share", metadata: {})
    member_event = AuditEvent.create!(workspace: member_workspace, actor: member, action: "share", metadata: {})

    scope = described_class.new(owner, AuditEvent.all).resolve

    expect(scope).to include(owner_event)
    expect(scope).not_to include(member_event)
  end
end
