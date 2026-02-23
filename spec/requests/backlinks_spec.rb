require "rails_helper"

RSpec.describe "Backlinks", type: :request do
  it "detects links from block content and renders backlinks on target pages" do
    owner = User.create!(email: "backlink-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backlinks", slug: "backlinks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target")

    block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "See [[Target]] for details." } ] } ]
      }
    )

    expect(PageLink.where(source_block: block, target_page: target_page)).to exist

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: target_page.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Backlinks")
    expect(response.body).to include("data-backlink-source=\"#{source_page.id}\"")
  end

  it "removes backlinks when links are removed from block content" do
    owner = User.create!(email: "backlink-owner-2@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backlinks 2", slug: "backlinks-2")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source 2")
    target_page = Page.create!(workspace: workspace, created_by: owner, title: "Target 2")

    block = Block.create!(
      workspace: workspace,
      page: source_page,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "See [[Target 2]]" } ] } ]
      }
    )
    expect(PageLink.where(source_block: block, target_page: target_page)).to exist

    block.update!(
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "No links now" } ] } ]
      }
    )

    sign_in owner
    get page_path(workspace_slug: workspace.slug, id: target_page.id)

    expect(response.body).not_to include("data-backlink-source=\"#{source_page.id}\"")
  end
end
