require "rails_helper"

RSpec.describe "Memberships", type: :request do
  it "logs role change events when owner updates a membership role" do
    owner = User.create!(email: "role-owner@example.com", password: "password123")
    member = User.create!(email: "role-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Roles", slug: "roles")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    membership = Membership.create!(workspace: workspace, user: member, role: :member)

    sign_in owner
    patch membership_path(workspace_slug: workspace.slug, id: membership.id), params: { membership: { role: "admin" } }

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(membership.reload.role).to eq("admin")
    event = AuditEvent.recent_first.first
    expect(event.action).to eq("role_change")
    expect(event.metadata["from_role"]).to eq("member")
    expect(event.metadata["to_role"]).to eq("admin")
  end

  it "prevents unauthorized users from changing roles" do
    owner = User.create!(email: "role-owner-2@example.com", password: "password123")
    member = User.create!(email: "role-member-2@example.com", password: "password123")
    guest = User.create!(email: "role-guest@example.com", password: "password123")
    workspace = Workspace.create!(name: "Roles 2", slug: "roles-2")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    membership = Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    sign_in guest
    patch membership_path(workspace_slug: workspace.slug, id: membership.id), params: { membership: { role: "admin" } }

    expect(response).to redirect_to(root_path)
    expect(membership.reload.role).to eq("member")
  end
end
