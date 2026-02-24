require "rails_helper"

RSpec.describe "Pages", type: :request do
  it "creates nested pages and renders hierarchy in workspace sidebar" do
    owner = User.create!(email: "pages-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge", slug: "knowledge")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    parent = Page.create!(workspace: workspace, created_by: owner, title: "Parent Page")
    sign_in owner

    post pages_path(workspace_slug: workspace.slug), params: { page: { title: "Child Page", parent_page_id: parent.id } }

    expect(response).to have_http_status(:redirect)
    get workspace_path(workspace.slug)
    expect(response.body).to include("Parent Page")
    expect(response.body).to include("Child Page")
  end

  it "hides archived pages from workspace sidebar" do
    owner = User.create!(email: "pages-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private", slug: "private")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Archive me")
    sign_in owner

    patch archive_page_path(workspace_slug: workspace.slug, id: page.id)
    get workspace_path(workspace.slug)

    expect(response.body).not_to include("Archive me")
  end

  it "supports page-level permission overrides: private, workspace, specific users" do
    owner = User.create!(email: "page-perms-owner@example.com", password: "password123")
    member = User.create!(email: "page-perms-member@example.com", password: "password123")
    outsider = User.create!(email: "page-perms-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Perms", slug: "perms")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Visibility Doc")

    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "private_page" } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(AuditEvent.recent_first.first.action).to eq("share")

    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "shared_to_workspace" } }
    sign_out owner
    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in owner
    patch permissions_page_path(workspace_slug: workspace.slug, id: page.id),
          params: { page: { permission_mode: "specific_users", shared_user_ids: [ member.id ] } }
    sign_out owner

    sign_in member
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in outsider
    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response).to have_http_status(:not_found)
  end

  it "blocks cross-workspace page access attempts" do
    owner = User.create!(email: "page-owner-cross@example.com", password: "password123")
    intruder = User.create!(email: "page-intruder-cross@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cross", slug: "cross")
    other_workspace = Workspace.create!(name: "Other", slug: "other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: intruder, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Protected")

    sign_in intruder
    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:not_found)
  end

  it "renders global shortcut UI containers on page view" do
    owner = User.create!(email: "page-shortcuts-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Shortcuts", slug: "shortcuts")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Shortcuts page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Quick switcher")
    expect(response.body).to include("Keyboard shortcuts")
    expect(response.body).to include("Cmd/Ctrl + K")
  end
end
