require "rails_helper"

RSpec.describe "API V1 Blocks", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "returns policy-scoped blocks only for visible pages" do
    owner = User.create!(email: "api-blocks-owner@example.com", password: "password123")
    member = User.create!(email: "api-blocks-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Blocks", slug: "api-blocks")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    visible_page = Page.create!(workspace: workspace, created_by: owner, title: "Visible page")
    hidden_page = Page.create!(workspace: workspace, created_by: owner, title: "Hidden page", permission_mode: :private_page)
    visible_block = Block.create!(workspace: workspace, page: visible_page, created_by: owner, block_type: "paragraph")
    Block.create!(workspace: workspace, page: hidden_page, created_by: owner, block_type: "paragraph")
    token = ApiToken.create!(user: member, name: "Member mobile")

    get "/api/v1/workspaces/#{workspace.slug}/pages/#{visible_page.id}/blocks", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    ids = json_body.fetch("data").map { |entry| entry.fetch("id") }
    expect(ids).to eq([ visible_block.id ])

    get "/api/v1/workspaces/#{workspace.slug}/pages/#{hidden_page.id}/blocks", headers: auth_headers(token)
    expect(response).to have_http_status(:not_found)
  end

  it "creates and updates blocks as json" do
    owner = User.create!(email: "api-blocks-write-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Blocks Write", slug: "api-blocks-write")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Blocks page")
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    post "/api/v1/workspaces/#{workspace.slug}/pages/#{page.id}/blocks",
         params: { block: { block_type: "paragraph" } },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    block_id = json_body.dig("data", "id")

    patch "/api/v1/workspaces/#{workspace.slug}/pages/#{page.id}/blocks/#{block_id}",
          params: {
            block: {
              block_type: "heading_1",
              content_json: {
                type: "doc",
                content: [ { type: "heading", attrs: { level: 1 }, content: [ { type: "text", text: "API heading" } ] } ]
              }
            }
          },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    updated = Block.find(block_id)
    expect(updated.block_type).to eq("heading_1")
    expect(updated.content_json.dig("content", 0, "type")).to eq("heading")
  end
end
