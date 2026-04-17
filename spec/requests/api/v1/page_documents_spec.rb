require "rails_helper"

RSpec.describe "API V1 Page documents", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  def paragraph_content(text)
    {
      "type" => "doc",
      "content" => [
        {
          "type" => "paragraph",
          "content" => [
            { "type" => "text", "text" => text }
          ]
        }
      ]
    }
  end

  it "exports a page as markdown over the API" do
    owner = User.create!(email: "api-page-doc-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Page Docs", slug: "api-page-docs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Release notes")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: owner,
      block_type: "heading_2",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "heading",
            "attrs" => { "level" => 2 },
            "content" => [ { "type" => "text", "text" => "Highlights" } ]
          }
        ]
      }
    )
    Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Shipped MCP bridge"))
    token = ApiToken.create!(user: owner, name: "Page markdown token")

    get "/api/v1/workspaces/#{workspace.slug}/pages/#{page.id}/markdown", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    expect(payload.dig("page", "id")).to eq(page.id)
    expect(payload.fetch("markdown")).to include("# Release notes")
    expect(payload.fetch("markdown")).to include("## Highlights")
    expect(payload.fetch("markdown")).to include("Shipped MCP bridge")
  end

  it "creates a new page from markdown over the API" do
    owner = User.create!(email: "api-page-doc-create@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Page Docs Create", slug: "api-page-docs-create")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    token = ApiToken.create!(user: owner, name: "Create markdown token")

    post "/api/v1/workspaces/#{workspace.slug}/pages/import_markdown",
         params: {
           page_document: {
             title: "Imported spec",
             markdown: "# Scope\n\nDocument body"
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    payload = json_body.fetch("data")
    created_page = Page.find(payload.dig("page", "id"))

    expect(created_page.title).to eq("Imported spec")
    expect(payload.fetch("imported_blocks").map { |entry| entry.fetch("block_type") }).to eq([ "heading_1", "paragraph" ])
    expect(created_page.blocks.active.ordered.last.search_text).to include("Document body")
  end

  it "appends markdown after a selected block over the API" do
    owner = User.create!(email: "api-page-doc-append@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Page Docs Append", slug: "api-page-docs-append")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Append target")
    first_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Anchor"))
    second_block = Block.create!(workspace: workspace, page: page, created_by: owner, block_type: "paragraph", content_json: paragraph_content("Tail"))
    token = ApiToken.create!(user: owner, name: "Append markdown token")

    post "/api/v1/workspaces/#{workspace.slug}/pages/#{page.id}/append_markdown",
         params: {
           page_document: {
             insert_after_block_id: first_block.id,
             markdown: "## Inserted\n\nMiddle paragraph"
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:ok)
    imported_ids = json_body.fetch("data").fetch("imported_blocks").map { |entry| entry.fetch("id") }
    ordered_ids = page.blocks.active.roots.ordered.pluck(:id)

    expect(ordered_ids).to eq([ first_block.id, *imported_ids, second_block.id ])
    expect(page.blocks.active.find(imported_ids.last).search_text).to include("Middle paragraph")
  end
end
