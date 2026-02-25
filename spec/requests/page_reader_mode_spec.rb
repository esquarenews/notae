require "rails_helper"

RSpec.describe "Page reader mode", type: :request do
  it "hides block chrome when remove blocks is enabled" do
    user = User.create!(email: "reader-mode-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Reader mode workspace", slug: "reader-mode-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Reader mode page")
    Block.create!(workspace: workspace, page: page, created_by: user, block_type: "paragraph")

    sign_in user

    patch page_path(workspace_slug: workspace.slug, id: page.id), params: { page: { remove_blocks: true } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.remove_blocks).to be(true)

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("is-reader-mode")
    expect(response.body).not_to include("notae-doc-handle")
    expect(response.body).not_to include("+ Add block")
  end

  it "locks the page into reader mode and hides other action tools" do
    user = User.create!(email: "reader-mode-lock-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Reader lock workspace", slug: "reader-lock-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Locked page")
    Block.create!(workspace: workspace, page: page, created_by: user, block_type: "paragraph")

    sign_in user

    patch page_path(workspace_slug: workspace.slug, id: page.id), params: { page: { locked: true } }
    expect(response).to redirect_to(page_path(workspace_slug: workspace.slug, id: page.id))
    expect(page.reload.locked).to be(true)

    get page_path(workspace_slug: workspace.slug, id: page.id)
    expect(response.body).to include("Page is locked. Other actions are unavailable.")
    expect(response.body).to include("notae-actions-panel is-page-locked")
    expect(response.body).not_to include("id=\"page-options-menu\"")
    expect(response.body).not_to include("id=\"page-comments-menu\"")
    expect(response.body).to include("is-reader-mode")
  end
end
