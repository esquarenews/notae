require "rails_helper"

RSpec.describe "API V1 Databases", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "lists policy-scoped databases and renders schema in show" do
    owner = User.create!(email: "api-databases-owner@example.com", password: "password123")
    outsider = User.create!(email: "api-databases-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Databases", slug: "api-databases")
    other_workspace = Workspace.create!(name: "API Databases Other", slug: "api-databases-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    database = Database.create!(workspace: workspace, name: "Tasks")
    other_database = Database.create!(workspace: other_workspace, name: "Private Tasks")
    status = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship mobile API")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status, value_text: "Todo")

    token = ApiToken.create!(user: owner, name: "Owner mobile")

    get "/api/v1/workspaces/#{workspace.slug}/databases", headers: auth_headers(token)
    expect(response).to have_http_status(:ok)
    ids = json_body.fetch("data").map { |entry| entry.fetch("id") }
    expect(ids).to include(database.id)
    expect(ids).not_to include(other_database.id)

    get "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}", headers: auth_headers(token)
    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    expect(payload.fetch("name")).to eq("Tasks")
    expect(payload.fetch("properties").length).to eq(1)
    expect(payload.fetch("rows").length).to eq(1)
    expect(payload.fetch("rows").first.fetch("cells").first.fetch("value_text")).to eq("Todo")
  end

  it "creates and updates databases as json" do
    owner = User.create!(email: "api-databases-write-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Databases Write", slug: "api-databases-write")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    post "/api/v1/workspaces/#{workspace.slug}/databases",
         params: { database: { name: "Roadmap" } },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    database_id = json_body.dig("data", "id")
    expect(Database.find(database_id).name).to eq("Roadmap")

    patch "/api/v1/workspaces/#{workspace.slug}/databases/#{database_id}",
          params: { database: { name: "Roadmap 2026" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(Database.find(database_id).name).to eq("Roadmap 2026")
  end

  it "archives database rows through the api" do
    owner = User.create!(email: "api-database-row-delete-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Database Row Delete", slug: "api-database-row-delete")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Pipeline")
    row = DbRow.create!(workspace: workspace, database: database, title: "Archive me")
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    delete "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}/rows/#{row.id}",
           headers: auth_headers(token),
           as: :json

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    expect(payload.fetch("id")).to eq(row.id)
    expect(payload.fetch("database_id")).to eq(database.id)
    expect(payload.fetch("archived_at")).to be_present
    expect(row.reload).to be_archived
  end

  it "sets clears and creates native row Nota links through the api" do
    owner = User.create!(email: "api-database-row-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Database Row Link", slug: "api-database-row-link")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Pipeline")
    row = DbRow.create!(workspace: workspace, database: database, title: "Create proposal")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Proposal notes")
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    patch "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}/rows/#{row.id}/linked_page",
          params: { db_row: { linked_page_id: linked_page.id } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    expect(payload.fetch("linked_page_id")).to eq(linked_page.id)
    expect(payload.fetch("linked_page").fetch("title")).to eq("Proposal notes")
    expect(row.reload.linked_page_id).to eq(linked_page.id)

    patch "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}/rows/#{row.id}/linked_page",
          params: { db_row: { link_action: "clear" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(json_body.dig("data", "linked_page_id")).to be_nil
    expect(row.reload.linked_page_id).to be_nil

    patch "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}/rows/#{row.id}/linked_page",
          params: { db_row: { link_action: "create_page" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    row.reload
    expect(row.linked_page).to be_present
    expect(row.linked_page.title).to eq("Create proposal")
    expect(json_body.dig("data", "linked_page", "id")).to eq(row.linked_page_id)
  end

  it "rejects row Nota links to pages outside the workspace" do
    owner = User.create!(email: "api-database-row-link-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Database Row Link Invalid", slug: "api-database-row-link-invalid")
    other_workspace = Workspace.create!(name: "API Database Row Link Other", slug: "api-database-row-link-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Pipeline")
    row = DbRow.create!(workspace: workspace, database: database, title: "Do not link")
    remote_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Remote notes")
    token = ApiToken.create!(user: owner, name: "Owner mobile")

    patch "/api/v1/workspaces/#{workspace.slug}/databases/#{database.id}/rows/#{row.id}/linked_page",
          params: { db_row: { linked_page_id: remote_page.id } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(422)
    expect(json_body.dig("error", "details", "linked_page_id")).to include("Linked page must reference an accessible page in this workspace")
    expect(row.reload.linked_page_id).to be_nil
  end
end
