require "rails_helper"

RSpec.describe "Databases", type: :request do
  it "defines schema, creates rows, and edits cells inline" do
    owner = User.create!(email: "database-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables", slug: "tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: { database: { name: "Tasks" } }

    database = Database.find_by!(name: "Tasks")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))

    post database_db_properties_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_property: { name: "Status", property_type: "text" } }

    db_property = database.db_properties.find_by!(name: "Status")
    expect(db_property.property_type).to eq("text")

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "Ship epic" } }

    db_row = database.db_rows.find_by!(title: "Ship epic")
    db_cell = db_row.db_cells.find_by!(db_property_id: db_property.id)
    expect(db_cell.value_text).to eq("")

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: db_cell.id),
          params: { db_cell: { value_text: "In Progress" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{db_row.id}"))
    expect(db_cell.reload.value_text).to eq("In Progress")
    expect(db_row.reload.data_json["Status"]).to eq("In Progress")
  end

  it "updates cells inline without a redirect for turbo-stream requests" do
    owner = User.create!(email: "database-inline-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Inline", slug: "tables-inline")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Tasks Inline")
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    db_row = DbRow.create!(workspace: workspace, database: database, title: "Inline row")
    db_cell = DbCell.create!(workspace: workspace, db_row: db_row, db_property: db_property, value_text: "Todo")
    sign_in owner

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: db_cell.id),
          params: { db_cell: { value_text: "Done" } },
          as: :turbo_stream

    expect(response).to have_http_status(:no_content)
    expect(response).not_to be_redirect
    expect(db_cell.reload.value_text).to eq("Done")
    expect(db_row.reload.data_json["Status"]).to eq("Done")
  end

  it "removes columns and dependent cells" do
    owner = User.create!(email: "database-remove-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Remove", slug: "tables-remove")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    db_property = DbProperty.create!(workspace: workspace, database:, name: "Priority", property_type: :text)
    db_row = DbRow.create!(workspace: workspace, database:, title: "Q1")
    DbCell.create!(workspace: workspace, db_row:, db_property:, value_text: "High")
    sign_in owner

    delete database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.db_properties.where(id: db_property.id)).to be_empty
    expect(DbCell.where(db_property_id: db_property.id)).to be_empty
  end

  it "sorts rows by column values" do
    owner = User.create!(email: "database-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Sort", slug: "tables-sort")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Leads")
    db_property = DbProperty.create!(workspace: workspace, database:, name: "Company", property_type: :text)
    alpha_row = DbRow.create!(workspace: workspace, database:, title: "Alpha Row")
    bravo_row = DbRow.create!(workspace: workspace, database:, title: "Bravo Row")
    DbCell.create!(workspace: workspace, db_row: alpha_row, db_property:, value_text: "Zulu")
    DbCell.create!(workspace: workspace, db_row: bravo_row, db_property:, value_text: "Acme")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: db_property.id, sort_direction: "asc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Bravo Row")).to be < response.body.index("Alpha Row")

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: db_property.id, sort_direction: "desc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Alpha Row")).to be < response.body.index("Bravo Row")
  end

  it "blocks non-members from accessing a workspace database" do
    owner = User.create!(email: "database-member-owner@example.com", password: "password123")
    outsider = User.create!(email: "database-member-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Private Tables", slug: "private-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Private DB")
    sign_in outsider

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:not_found)
  end
end
