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

  it "supports typed property filtering and sorting for number, date, and checkbox columns" do
    owner = User.create!(email: "database-typed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Typed tables", slug: "typed-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Typed DB")
    estimate_property = DbProperty.create!(workspace: workspace, database: database, name: "Estimate", property_type: :number)
    due_property = DbProperty.create!(workspace: workspace, database: database, name: "Due", property_type: :date)
    done_property = DbProperty.create!(workspace: workspace, database: database, name: "Done", property_type: :checkbox)
    low_row = DbRow.create!(workspace: workspace, database: database, title: "Low estimate")
    high_row = DbRow.create!(workspace: workspace, database: database, title: "High estimate")
    DbCell.create!(workspace: workspace, db_row: low_row, db_property: estimate_property, value_text: "2")
    DbCell.create!(workspace: workspace, db_row: high_row, db_property: estimate_property, value_text: "10")
    DbCell.create!(workspace: workspace, db_row: low_row, db_property: due_property, value_text: "2026-03-05")
    DbCell.create!(workspace: workspace, db_row: high_row, db_property: due_property, value_text: "2026-03-22")
    low_done = DbCell.create!(workspace: workspace, db_row: low_row, db_property: done_property, value_text: "false")
    DbCell.create!(workspace: workspace, db_row: high_row, db_property: done_property, value_text: "true")
    sign_in owner

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: low_done.id),
          params: { db_cell: { value_text: "on" } }
    expect(low_done.reload.value_text).to eq("true")

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: estimate_property.id, sort_direction: "asc")
    expect(response).to have_http_status(:ok)
    expect(response.body.index("Low estimate")).to be < response.body.index("High estimate")

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: due_property.id, sort_direction: "desc")
    expect(response).to have_http_status(:ok)
    expect(response.body.index("High estimate")).to be < response.body.index("Low estimate")

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      filter_property_id: done_property.id,
      filter_value: "true"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Low estimate")
    expect(response.body).to include("High estimate")

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      filter_property_id: done_property.id,
      filter_value: "false"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Low estimate")
    expect(response.body).not_to include("High estimate")
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

  it "groups board columns by select property and persists drag ordering" do
    owner = User.create!(email: "database-board-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board tables", slug: "board-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Kanban")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    todo_row = DbRow.create!(workspace: workspace, database: database, title: "Todo item")
    moved_row = DbRow.create!(workspace: workspace, database: database, title: "Move me")
    doing_row = DbRow.create!(workspace: workspace, database: database, title: "Doing item")
    DbCell.create!(workspace: workspace, db_row: todo_row, db_property: status_property, value_text: "Todo")
    DbCell.create!(workspace: workspace, db_row: moved_row, db_property: status_property, value_text: "Todo")
    DbCell.create!(workspace: workspace, db_row: doing_row, db_property: status_property, value_text: "Doing")
    board_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Board",
      view_type: :board,
      config_json: { "group_property_id" => status_property.id },
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Todo")
    expect(response.body).to include("Doing")
    expect(response.body).to include("Move me")

    patch move_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: moved_row.id),
          params: { property_id: status_property.id, target_value: "Doing", target_index: 0 },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(moved_row.db_cells.find_by!(db_property: status_property).reload.value_text).to eq("Doing")

    doing_row_ids = DbCell.where(db_property: status_property, value_text: "Doing").pluck(:db_row_id)
    ordered_doing_ids = DbRow.for_database(database).active.ordered.where(id: doing_row_ids).pluck(:id)
    expect(ordered_doing_ids.first).to eq(moved_row.id)

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Move me")).to be < response.body.index("Doing item")
  end

  it "renders board view with more than 500 rows" do
    owner = User.create!(email: "database-board-scale-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board scale tables", slug: "board-scale-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Scale board")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    board_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Scale board view",
      view_type: :board,
      config_json: { "group_property_id" => status_property.id },
      default: true
    )
    510.times do |index|
      row = DbRow.create!(workspace: workspace, database: database, title: "Row #{index}")
      DbCell.create!(
        workspace: workspace,
        db_row: row,
        db_property: status_property,
        value_text: index.even? ? "Todo" : "Doing"
      )
    end
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("510 rows")
    expect(response.body).to include("Todo")
    expect(response.body).to include("Doing")
  end

  it "requires a date property for calendar views" do
    owner = User.create!(email: "database-calendar-requires-date-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Calendar requires date", slug: "calendar-requires-date")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Calendar DB")
    calendar_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Calendar",
      view_type: :calendar,
      config_json: {}
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: calendar_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendar view requires a property with type")
  end

  it "renders month calendar and creates rows from a selected date" do
    owner = User.create!(email: "database-calendar-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Calendar tables", slug: "calendar-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Calendar DB")
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    calendar_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Month",
      view_type: :calendar,
      config_json: { "date_property_id" => due_date_property.id },
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: calendar_view.id, month: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("March 2026")
    expect(response.body).to include("Sun")

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: {
           db_row: { title: "" },
           view_id: calendar_view.id,
           month: "2026-03-01",
           date_property_id: due_date_property.id,
           date_value: "2026-03-15"
         }

    expect(response).to redirect_to(
      database_path(workspace_slug: workspace.slug, id: database.id, view_id: calendar_view.id.to_s, month: "2026-03-01")
    )

    created_row = database.db_rows.order(:created_at).last
    created_cell = created_row.db_cells.find_by!(db_property: due_date_property)
    expect(created_row.title).to eq("Untitled row")
    expect(created_cell.value_text).to eq("2026-03-15")
  end

  it "updates the date property when rows are dragged between calendar days" do
    owner = User.create!(email: "database-calendar-drag-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Calendar drag tables", slug: "calendar-drag-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Calendar Drag DB")
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Move date")
    DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-03-10")
    calendar_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Calendar",
      view_type: :calendar,
      config_json: { "date_property_id" => due_date_property.id },
      default: true
    )
    sign_in owner

    patch move_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: {
            property_id: due_date_property.id,
            target_value: "2026-03-20",
            target_index: 0,
            view_id: calendar_view.id,
            month: "2026-03-01"
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(row.db_cells.find_by!(db_property: due_date_property).reload.value_text).to eq("2026-03-20")
  end

  it "saves view configs and supports switching and default selection" do
    owner = User.create!(email: "database-view-config-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "View config tables", slug: "view-config-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "View config DB")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    sign_in owner

    post database_database_views_path(workspace_slug: workspace.slug, database_id: database.id),
         params: {
           database_view: {
             name: "Filtered table",
             view_type: "table",
             sort_property_id: status_property.id,
             sort_direction: "desc",
             filter_property_id: status_property.id,
             filter_value: "Done",
             default: true
           }
         }

    filtered_view = database.database_views.find_by!(name: "Filtered table")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: filtered_view.id))
    expect(filtered_view.default).to eq(true)
    expect(filtered_view.config_json).to include(
      "sort_property_id" => status_property.id,
      "sort_direction" => "desc",
      "filter_property_id" => status_property.id,
      "filter_value" => "Done"
    )

    post database_database_views_path(workspace_slug: workspace.slug, database_id: database.id),
         params: {
           database_view: {
             name: "Board view",
             view_type: "board",
             group_property_id: status_property.id
           }
         }

    board_view = database.database_views.find_by!(name: "Board view")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id))

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Board view")

    patch database_default_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: board_view.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id))
    expect(board_view.reload.default).to eq(true)
    expect(filtered_view.reload.default).to eq(false)

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Board view")
  end

  it "renders list and gallery views" do
    owner = User.create!(email: "database-list-gallery-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "List gallery tables", slug: "list-gallery-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Content DB")
    category_property = DbProperty.create!(workspace: workspace, database: database, name: "Category", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Launch post")
    DbCell.create!(workspace: workspace, db_row: row, db_property: category_property, value_text: "Announcements")
    list_view = DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "List view", view_type: :list)
    gallery_view = DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Gallery view", view_type: :gallery)
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: list_view.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-db-list-view")
    expect(response.body).to include("Launch post")
    expect(response.body).to include("Announcements")

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: gallery_view.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-db-gallery-view")
    expect(response.body).to include("Launch post")
    expect(response.body).to include("Announcements")
  end

  it "renders the minimal table shell with add-property and quick new-row controls" do
    owner = User.create!(email: "database-table-shell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Table shell tables", slug: "table-shell-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "New database")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Aa")
    expect(response.body).to include("Name")
    expect(response.body).to include("+ Add property")
    expect(response.body).to include("New page")
    expect(response.body).to include("Database controls")
  end

  it "updates row titles inline and normalizes blank titles" do
    owner = User.create!(email: "database-row-update-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row update tables", slug: "row-update-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row update DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Original title")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Renamed row" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.reload.title).to eq("Renamed row")

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "   " } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.reload.title).to eq("Untitled row")
  end

  it "archives rows and excludes them from active database views" do
    owner = User.create!(email: "database-row-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row archive tables", slug: "row-archive-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row archive DB")
    kept_row = DbRow.create!(workspace: workspace, database: database, title: "Keep me")
    archived_row = DbRow.create!(workspace: workspace, database: database, title: "Archive me")
    sign_in owner

    delete database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: archived_row.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(archived_row.reload.archived_at).to be_present

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Keep me")
    expect(response.body).not_to include("Archive me")
    expect(kept_row.reload.archived_at).to be_nil
  end
end
