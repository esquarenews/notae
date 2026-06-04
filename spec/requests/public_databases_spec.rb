require "rails_helper"

RSpec.describe "Public databases", type: :request do
  it "renders a shared grid in read-only mode" do
    owner = User.create!(email: "public-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public grid workspace", slug: "public-grid-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Shared grid")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Row one")
    DbCell.create!(workspace: workspace, db_row: row, db_property: property, value_text: "In progress")
    share_link = DatabaseShareLink.create!(workspace: workspace, database: database, created_by: owner)

    get public_database_share_path(token: share_link.token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared grid")
    expect(response.body).to include("Row one")
    expect(response.body).to include("In progress")
    expect(response.body).to include("Read-only share")
    expect(response.body).to include("This shared grid is view-only here.")
    expect(response.headers["Content-Security-Policy"]).to include("script-src 'none'")
    expect(response.headers["Content-Security-Policy"]).to include("form-action 'none'")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
    expect(share_link.reload.last_viewed_at).to be_present
  end

  it "returns 404 for invalid, expired, or revoked grid tokens" do
    owner = User.create!(email: "public-grid-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Invalid grid share workspace", slug: "invalid-grid-share-workspace")
    database = Database.create!(workspace: workspace, name: "Invalid token grid")
    expired = DatabaseShareLink.create!(workspace: workspace, database: database, created_by: owner, expires_at: 1.minute.ago)
    revoked = DatabaseShareLink.create!(workspace: workspace, database: database, created_by: owner)
    revoked.revoke!

    get public_database_share_path(token: "missing-token")
    expect(response).to have_http_status(:not_found)

    get public_database_share_path(token: expired.token)
    expect(response).to have_http_status(:not_found)

    get public_database_share_path(token: revoked.token)
    expect(response).to have_http_status(:not_found)
  end

  it "labels public grid shares with the selected access level" do
    owner = User.create!(email: "public-grid-edit-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Public edit grid workspace", slug: "public-edit-grid-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Edit shared grid")
    share_link = DatabaseShareLink.create!(workspace: workspace, database: database, created_by: owner, access_level: "edit")

    get public_database_share_path(token: share_link.token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Edit share")
    expect(response.body).to include("This link was created with edit access.")
  end
end
