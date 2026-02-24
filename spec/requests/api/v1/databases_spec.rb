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
end
