require "rails_helper"

RSpec.describe "API V1 Pages", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "requires a valid bearer token" do
    user = User.create!(email: "api-pages-auth@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Pages Auth", slug: "api-pages-auth")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    get "/api/v1/workspaces/#{workspace.slug}/pages"

    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("unauthorized")
  end

  it "rejects abnormally long bearer token headers" do
    user = User.create!(email: "api-pages-long-token@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Pages long token", slug: "api-pages-long-token")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    long_token = "a" * 2_048

    get "/api/v1/workspaces/#{workspace.slug}/pages",
        headers: { "Authorization" => "Bearer #{long_token}", "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(json_body.dig("error", "code")).to eq("unauthorized")
  end

  it "returns policy-scoped pages only" do
    owner = User.create!(email: "api-pages-owner@example.com", password: "password123")
    member = User.create!(email: "api-pages-member@example.com", password: "password123")
    outsider = User.create!(email: "api-pages-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Pages", slug: "api-pages")
    other_workspace = Workspace.create!(name: "API Pages Other", slug: "api-pages-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    shared_page = Page.create!(workspace: workspace, created_by: owner, title: "Shared page")
    private_page = Page.create!(workspace: workspace, created_by: owner, title: "Private page", permission_mode: :private_page)
    specific_page = Page.create!(workspace: workspace, created_by: owner, title: "Specific page", permission_mode: :specific_users)
    PageShare.create!(page: specific_page, user: member, created_by: owner)
    hidden_specific_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Hidden specific page",
      permission_mode: :specific_users
    )
    other_workspace_page = Page.create!(workspace: other_workspace, created_by: outsider, title: "Other page")

    token = ApiToken.create!(user: member, name: "Member mobile")
    get "/api/v1/workspaces/#{workspace.slug}/pages", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    response_ids = json_body.fetch("data").map { |entry| entry.fetch("id") }

    expect(response_ids).to include(shared_page.id, specific_page.id)
    expect(response_ids).not_to include(private_page.id)
    expect(response_ids).not_to include(hidden_specific_page.id)
    expect(response_ids).not_to include(other_workspace_page.id)
  end

  it "creates and updates pages as json" do
    owner = User.create!(email: "api-pages-write-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Pages Write", slug: "api-pages-write")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    post "/api/v1/workspaces/#{workspace.slug}/pages",
         params: { page: { title: "Created from API" } },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    created_page_id = json_body.dig("data", "id")
    expect(Page.find(created_page_id).title).to eq("Created from API")

    patch "/api/v1/workspaces/#{workspace.slug}/pages/#{created_page_id}",
          params: { page: { title: "Updated from API" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(Page.find(created_page_id).title).to eq("Updated from API")
  end

  it "supports title and page-kind filtering for page discovery" do
    owner = User.create!(email: "api-pages-filter-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Pages Filter", slug: "api-pages-filter")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    token = ApiToken.create!(user: owner, name: "Owner filter token")

    Page.create!(workspace: workspace, created_by: owner, title: "Kickoff notes", page_kind: "meeting_note")
    Page.create!(workspace: workspace, created_by: owner, title: "Product brief", page_kind: "nota")
    Page.create!(workspace: workspace, created_by: owner, title: "Kickoff checklist", page_kind: "nota")

    get "/api/v1/workspaces/#{workspace.slug}/pages",
        params: { q: "kick", page_kind: "meeting_note", limit: 5 },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")

    expect(payload.map { |entry| entry.fetch("title") }).to eq([ "Kickoff notes" ])
    expect(payload.first.fetch("permission_mode")).to eq("shared_to_workspace")
  end
end
