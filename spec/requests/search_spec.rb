require "rails_helper"

RSpec.describe "Search", type: :request do
  it "returns highlighted workspace-scoped results across pages, blocks, and rows" do
    user = User.create!(email: "search-user@example.com", password: "password123")
    workspace = Workspace.create!(name: "Searchable", slug: "searchable")
    other_workspace = Workspace.create!(name: "Other", slug: "other-search")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Alpha Planning")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "alpha roadmap block" } ] } ]
      }
    )

    database = Database.create!(workspace: workspace, name: "Tasks")
    DbRow.create!(workspace: workspace, database: database, title: "Alpha row", data_json: { notes: "track alpha launch" })

    Page.create!(workspace: other_workspace, created_by: user, title: "Alpha Secret")

    sign_in user
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "alpha" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-utility-page")
    expect(response.body).to include("notae-utility-search-form")
    expect(response.body).to include("notae-utility-result-item")
    expect(response.body).to include("Page")
    expect(response.body).to include("Block")
    expect(response.body).to include("Row")
    expect(response.body).to match(/<mark>alpha<\/mark>/i)
    expect(response.body).not_to include("Alpha Secret")
  end

  it "blocks search access for users outside the workspace" do
    owner = User.create!(email: "search-owner@example.com", password: "password123")
    outsider = User.create!(email: "search-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private Search", slug: "private-search")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in outsider
    get workspace_search_path(workspace_slug: workspace.slug), params: { q: "private" }

    expect(response).to have_http_status(:not_found)
  end
end
