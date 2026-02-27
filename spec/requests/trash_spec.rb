require "rails_helper"

RSpec.describe "Trash", type: :request do
  it "shows archived pages scoped to current workspace and supports search" do
    owner = User.create!(email: "trash-owner@example.com", password: "password123")
    outsider = User.create!(email: "trash-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Trash workspace", slug: "trash-workspace")
    other_workspace = Workspace.create!(name: "Other trash workspace", slug: "other-trash-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    archived_page = Page.create!(workspace: workspace, created_by: owner, title: "Old Spec")
    active_page = Page.create!(workspace: workspace, created_by: owner, title: "Current Spec")
    outside_archived_page = Page.create!(workspace: other_workspace, created_by: outsider, title: "Outside Old Spec")
    archived_page.archive!
    outside_archived_page.archive!

    sign_in owner
    get workspace_trash_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Old Spec")
    expect(response.body).not_to include("Outside Old Spec")

    get workspace_trash_path(workspace_slug: workspace.slug), params: { q: "Not present" }
    expect(response.body).to include("No results")
  end

  it "restores and permanently deletes archived pages from trash actions" do
    owner = User.create!(email: "trash-restore-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Trash restore workspace", slug: "trash-restore-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    restorable_page = Page.create!(workspace: workspace, created_by: owner, title: "Restore me")
    deletable_page = Page.create!(workspace: workspace, created_by: owner, title: "Delete me")
    restorable_page.archive!
    deletable_page.archive!
    sign_in owner

    patch restore_page_path(workspace_slug: workspace.slug, id: restorable_page.id)
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: restorable_page.id))
    expect(restorable_page.reload.archived_at).to be_nil

    expect do
      delete page_path(workspace_slug: workspace.slug, id: deletable_page.id)
    end.to change(Page, :count).by(-1)
    expect(response).to redirect_to(workspace_trash_path(workspace_slug: workspace.slug))
  end

  it "lists and restores archived grids" do
    owner = User.create!(email: "trash-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Trash grid workspace", slug: "trash-grid-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    archived_grid = Database.create!(workspace: workspace, name: "Old grid", archived_at: Time.current)
    sign_in owner

    get workspace_trash_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Old grid")

    patch restore_database_path(workspace_slug: workspace.slug, id: archived_grid.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: archived_grid.id))
    expect(archived_grid.reload.archived_at).to be_nil
  end
end
