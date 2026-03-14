require "rails_helper"

RSpec.describe AuditEventPolicy::Scope do
  it "returns audit events only for admin, owner, and auditor memberships" do
    owner = User.create!(email: "audit-owner@example.com", password: "password123")
    auditor = User.create!(email: "audit-auditor@example.com", password: "password123")
    member = User.create!(email: "audit-member@example.com", password: "password123")
    owner_workspace = Workspace.create!(name: "Owner Audit", slug: "owner-audit")
    auditor_workspace = Workspace.create!(name: "Auditor Audit", slug: "auditor-audit")
    member_workspace = Workspace.create!(name: "Member Audit", slug: "member-audit")
    Membership.create!(workspace: owner_workspace, user: owner, role: :owner)
    Membership.create!(workspace: auditor_workspace, user: auditor, role: :auditor)
    Membership.create!(workspace: member_workspace, user: owner, role: :member)
    Membership.create!(workspace: member_workspace, user: member, role: :owner)
    owner_event = AuditEvent.create!(workspace: owner_workspace, actor: owner, action: "share", metadata: {})
    auditor_event = AuditEvent.create!(workspace: auditor_workspace, actor: auditor, action: "agent_action_approved", metadata: {})
    member_event = AuditEvent.create!(workspace: member_workspace, actor: member, action: "share", metadata: {})

    owner_scope = described_class.new(owner, AuditEvent.all).resolve
    auditor_scope = described_class.new(auditor, AuditEvent.all).resolve

    expect(owner_scope).to include(owner_event)
    expect(owner_scope).not_to include(member_event)
    expect(auditor_scope).to include(auditor_event)
    expect(auditor_scope).not_to include(owner_event)
    expect(auditor_scope).not_to include(member_event)
  end
end
