require "rails_helper"

RSpec.describe "Databases", type: :request do
  it "creates a grid when optional database columns are unavailable" do
    owner = User.create!(email: "database-legacy-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables legacy", slug: "tables-legacy")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    original_column_names = Database.column_names
    allow(Database).to receive(:column_names).and_return(original_column_names - %w[locked])
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: { database: { name: "Legacy Tasks" } }

    database = Database.find_by!(workspace: workspace, name: "Legacy Tasks")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
  end

  it "auto-suffixes quick-create untitled grid names when a collision exists" do
    owner = User.create!(email: "database-quick-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Quick create tables", slug: "quick-create-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Database.create!(workspace: workspace, name: "Untitled grid")
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: { quick_create: "1", database: { name: "Untitled grid" } }

    created_database = workspace.databases.order(:created_at).last
    expect(created_database.name).to eq("Untitled grid 2")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: created_database.id))
  end

  it "creates a tasks template with task columns, default status, and dropdown options" do
    owner = User.create!(email: "database-template-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Template tables", slug: "template-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: { quick_create: "1", template: "tasks", database: { name: "Tasks grid" } }

    database = workspace.databases.order(:created_at).last
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Status", "select" ],
        [ "Date created", "date" ],
        [ "Due date", "date" ],
        [ "Notes", "text" ]
      ]
    )

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "Task one" } }

    row = database.db_rows.order(:created_at).last
    status_property = database.db_properties.find_by!(name: "Status")
    status_cell = row.db_cells.find_by!(db_property: status_property)
    date_created_property = database.db_properties.find_by!(name: "Date created")
    expect(status_cell.value_text).to eq("not started")
    expect(row.db_cells.find_by!(db_property: date_created_property).value_text).to eq(Date.current.iso8601)

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("<datalist")

    document = Nokogiri::HTML(response.body)
    status_dropdown = document.at_css("select.notae-db-cell-select-status")
    expect(status_dropdown).to be_present
    status_option_values = status_dropdown.css("option").map { |option| option["value"] }.compact
    expect(status_option_values).to include("", "not started", "started", "overdue", "hold", "done")
    expect(status_dropdown.at_css("option[selected]")&.[]("value")).to eq("not started")
  end

  it "does not auto-seed hidden property cells during grid render" do
    owner = User.create!(email: "database-hidden-cells-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Hidden cells", slug: "hidden-cells")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Scoped cell loading")
    visible_property = DbProperty.create!(workspace: workspace, database: database, name: "Visible", property_type: :text)
    hidden_property = DbProperty.create!(workspace: workspace, database: database, name: "Hidden", property_type: :text)
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "visible_property_ids" => [ visible_property.id.to_s ] }
    )
    row = DbRow.create!(workspace: workspace, database: database, title: "Row one")
    DbCell.create!(workspace: workspace, db_row: row, db_property: visible_property, value_text: "Visible value")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(DbCell.exists?(db_row: row, db_property: hidden_property)).to be(false)
  end

  it "greys rows when status is done and restores color when reopened" do
    owner = User.create!(email: "database-status-color-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Status color tables", slug: "status-color-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Status colors")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Task row")
    status_cell = DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    sign_in owner

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: status_cell.id),
          params: { db_cell: { value_text: "done" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.reload.row_text_color).to eq("gray")

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: status_cell.id),
          params: { db_cell: { value_text: "started" } }
    expect(row.reload.row_text_color).to eq("default")
  end

  it "converts a grid to kanban and groups by status" do
    owner = User.create!(email: "database-kanbanize-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kanbanize tables", slug: "kanbanize-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Kanbanize me")
    sign_in owner

    post kanbanize_database_path(workspace_slug: workspace.slug, id: database.id)

    database.reload
    board_view = database.database_views.find_by!(view_type: :board)
    status_property = database.db_properties.find { |property| property.name == "Status" }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id))
    expect(status_property).to be_present
    expect(status_property.property_type).to eq("select")
    expect(board_view.config_json["group_property_id"]).to eq(status_property.id)
  end

  it "defines schema, creates rows, and edits cells inline" do
    owner = User.create!(email: "database-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables", slug: "tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: { database: { name: "Tasks" } }

    database = Database.find_by!(name: "Tasks")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.database_views.where(name: "Table", view_type: :table, default: true)).to exist

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

  it "updates cells inline and refreshes topbar edited metadata for turbo-stream requests" do
    owner = User.create!(email: "database-inline-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Inline", slug: "tables-inline")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Tasks Inline")
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    db_row = DbRow.create!(workspace: workspace, database: database, title: "Inline row")
    db_cell = DbCell.create!(workspace: workspace, db_row: db_row, db_property: db_property, value_text: "Todo")
    database.update_column(:updated_at, 2.days.ago)
    previous_database_updated_at = database.reload.updated_at
    sign_in owner

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: db_cell.id),
          params: { db_cell: { value_text: "Done" } },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="update" target="database_topbar_edited_at"')
    expect(response.body).to include("Edited")
    expect(db_cell.reload.value_text).to eq("Done")
    expect(db_row.reload.data_json["Status"]).to eq("Done")
    expect(database.reload.updated_at).to be > previous_database_updated_at
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

  it "persists table header sorts in the current view config" do
    owner = User.create!(email: "database-persistent-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Persistent sort tables", slug: "persistent-sort-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Pipeline")
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Company", property_type: :text)
    alpha_row = DbRow.create!(workspace: workspace, database: database, title: "Alpha Row")
    bravo_row = DbRow.create!(workspace: workspace, database: database, title: "Bravo Row")
    DbCell.create!(workspace: workspace, db_row: alpha_row, db_property: db_property, value_text: "Zulu")
    DbCell.create!(workspace: workspace, db_row: bravo_row, db_property: db_property, value_text: "Acme")
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    sort_form = html.at_css("form.notae-db-grid-property-sort-form[action='#{database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id)}']")
    expect(sort_form).to be_present
    expect(sort_form.at_css("input[name='_method'][value='patch']")).to be_present
    expect(sort_form.at_css("input[name='database_view[sort_property_id]'][value='#{db_property.id}']")).to be_present
    expect(sort_form.at_css("input[name='database_view[sort_direction]'][value='asc']")).to be_present

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              sort_property_id: db_property.id,
              sort_direction: "asc"
            }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id))
    expect(view.reload.config_json).to include(
      "sort_property_id" => db_property.id,
      "sort_direction" => "asc"
    )

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Bravo Row")).to be < response.body.index("Alpha Row")
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

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      filter_property_id: due_property.id,
      filter_operator: "before",
      filter_value: "2026-03-10"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Low estimate")
    expect(response.body).not_to include("High estimate")

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      filter_property_id: estimate_property.id,
      filter_operator: "after",
      filter_value: "5"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Low estimate")
    expect(response.body).to include("High estimate")
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

  it "supports grid-level permission overrides: private, workspace, and specific users" do
    owner = User.create!(email: "database-perms-owner@example.com", password: "password123")
    member = User.create!(email: "database-perms-member@example.com", password: "password123")
    outsider = User.create!(email: "database-perms-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database perms", slug: "database-perms")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Visibility grid")

    sign_in owner
    patch permissions_database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { permission_mode: "private_database" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(AuditEvent.recent_first.first.action).to eq("share")

    sign_out owner
    sign_in member
    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:not_found)

    sign_out member
    sign_in owner
    patch permissions_database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { permission_mode: "shared_to_workspace" } }
    sign_out owner
    sign_in member
    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)

    sign_out member
    sign_in owner
    patch permissions_database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { permission_mode: "specific_users", shared_user_ids: [ member.id ] } }
    sign_out owner

    sign_in member
    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)

    sign_out member
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

  it "renders all task status columns in board view even when some are empty" do
    owner = User.create!(email: "database-board-all-status-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board all status tables", slug: "board-all-status-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task board")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Started task")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    board_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Task board",
      view_type: :board,
      config_json: { "group_property_id" => status_property.id },
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("not started")
    expect(response.body).to include("started")
    expect(response.body).to include("overdue")
    expect(response.body).to include("hold")
    expect(response.body).to include("done")

    document = Nokogiri::HTML.parse(response.body)
    started_column = document.at_css(".notae-db-board-column-title.is-status-started")
    done_column = document.at_css(".notae-db-board-column-title.is-status-done")

    expect(started_column&.text.to_s).to include("started")
    expect(done_column&.text.to_s).to include("done")
  end

  it "renders non-grouped property values inside board cards" do
    owner = User.create!(email: "database-board-details-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board detail tables", slug: "board-detail-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Board details")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    notes_property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Card detail row")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-03-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: notes_property, value_text: "Follow up with vendor")
    board_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Board details",
      view_type: :board,
      config_json: { "group_property_id" => status_property.id },
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Due date")
    expect(response.body).to include("2026-03-12")
    expect(response.body).to include("Notes")
    expect(response.body).to include("Follow up with vendor")
  end

  it "updates a row title over json for inline board edits" do
    owner = User.create!(email: "database-board-json-title-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board json title tables", slug: "board-json-title-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Board json title")
    row = DbRow.create!(workspace: workspace, database: database, title: "Before edit")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "After edit", autosave_title: "1" } },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["title"]).to eq("After edit")
    expect(response.parsed_body["topbar_edited_at_html"]).to include("Edited")
    expect(row.reload.title).to eq("After edit")
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

  it "renders the minimal table shell with add-property and a bottom new-row control" do
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
    expect(response.body).to include("notae-db-new-row-trigger-form")
    expect(response.body).to include("notae-db-grid-add-row-control")
    expect(response.body).to include("+ New row")
    expect(response.body).not_to include("notae-db-toolbar-new")
    expect(response.body).not_to include("notae-db-grid-new-row")
    expect(response.body).not_to include("Link &amp; add row")
    expect(response.body).to include("Add icon")
    expect(response.body).to include("Add cover")
    expect(response.body).to include("Add description")
    expect(response.body).to include('aria-label="Add icon"')
    expect(response.body).to include('aria-label="Add cover"')
    expect(response.body).to include('aria-label="Add description"')
    expect(response.body).to include('class="notae-page-header-action-label"')
    expect(response.body).to include("View settings")
    expect(response.body).to include("Layout")
    expect(response.body).to include("Property visibility")
    expect(response.body).to include("Conditional color")
    expect(response.body).to include("Lock grid")
    expect(response.body).to include("notae-actions-font-grid")
    expect(response.body).to include("Default")
    expect(response.body).to include("Serif")
    expect(response.body).to include("Mono")
    expect(response.body).to include("Copy link to view")
    expect(response.body).to include("Copy page contents")
    expect(response.body).to include("Duplicate")
    expect(response.body).to include("Move to")
    expect(response.body).to include("Move to Trash")
    expect(response.body).to include("Options")
    expect(response.body).to include("Permissions")
    expect(response.body).to include("Public share links")
    expect(response.body).to include("Archived rows")
    expect(response.body).to include("Small text")
    expect(response.body).to include("Undo")
    expect(response.body).to include("Export")
    expect(response.body).to include("Updates &amp; analytics")
    expect(response.body).to include("Version history")
    expect(response.body).to include("notae-db-actions-menu")
    expect(response.body).to include("data-copy-text-feedback")
    expect(response.body).to include("http://www.example.com/w/#{workspace.slug}/databases/#{database.id}")
    expect(response.body).to include("Timeline")
    expect(response.body).to include("Kanban board")
    expect(response.body).to include("Map")
    expect(response.body).not_to include("Open linked page")
    expect(response.body).to include("notae-page-header-cover-panel")
    expect(response.body).to include("notae-cover-picker-panel is-embedded")
    expect(response.body).to include("data-controller=\"cover-carousel\"")
    expect(response.body).to include("Move up")
    expect(response.body).to include("Move down")
    expect(response.body).to include("notae-db-settings-menu")
    expect(response.body).to include("🧠")
    expect(response.body).to include("name=\"database[name]\"")
    expect(response.body).to include("notae-page-title-input")
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DatabasesController#show")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    expect(response.body).not_to include("db-edit-view-panel")
    expect(response.body).not_to include("notae-db-view-plus")

    html = Nokogiri::HTML(response.body)
    title_field = html.at_css("textarea.notae-page-title-input[name='database[name]']")
    expect(title_field).to be_present
    expect(title_field["rows"]).to eq("1")
    permissions_form = html.at_css("form[action*='/permissions']")
    expect(permissions_form).to be_present
    expect(permissions_form.at_css("select[name='database[permission_mode]']")).to be_present
    expect(permissions_form.at_css("input[type='checkbox'][name='database[shared_user_ids][]']")).to be_present
    table_rows = html.css(".notae-db-grid tbody tr")
    expect(table_rows).not_to be_empty
    expect(table_rows.last["class"]).to include("notae-db-grid-add-row-control")
    expect(table_rows.map { |row| row["class"] }.join(" ")).not_to include("notae-db-grid-new-row")
  end

  it "applies property visibility from view config to table columns" do
    owner = User.create!(email: "database-property-visibility-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Property visibility tables", slug: "property-visibility-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Visibility DB")
    visible_property = DbProperty.create!(workspace: workspace, database: database, name: "Visible column", property_type: :text)
    hidden_property = DbProperty.create!(workspace: workspace, database: database, name: "Hidden column", property_type: :text)
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "visible_property_ids" => [ visible_property.id ] }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    visible_headers = html.css(".notae-db-grid-property-link").map { |node| node.text.strip }
    expect(visible_headers).to include("Visible column")
    expect(visible_headers).not_to include("Hidden column")
  end

  it "includes newly added columns in explicit view visibility config" do
    owner = User.create!(email: "database-property-new-visible-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Property visibility new columns", slug: "property-visibility-new-columns")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Visibility New DB")
    visible_property = DbProperty.create!(workspace: workspace, database: database, name: "Visible column", property_type: :text)
    DbProperty.create!(workspace: workspace, database: database, name: "Hidden column", property_type: :text)
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "visible_property_ids" => [ visible_property.id ] }
    )
    sign_in owner

    post database_db_properties_path(workspace_slug: workspace.slug, database_id: database.id, view_id: view.id),
         params: { db_property: { name: "Fresh column", property_type: "text" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id))
    created_property = database.db_properties.find_by!(name: "Fresh column")
    configured_visible_ids = Array(view.reload.config_json["visible_property_ids"]).map(&:to_s)
    expect(configured_visible_ids).to include(visible_property.id.to_s, created_property.id.to_s)

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    visible_headers = html.css(".notae-db-grid-property-link").map { |node| node.text.strip }
    expect(visible_headers).to include("Visible column", "Fresh column")
    expect(visible_headers).not_to include("Hidden column")
  end

  it "persists resized table column widths in the active grid view" do
    owner = User.create!(email: "database-column-width-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Column width tables", slug: "column-width-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Column width DB")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              column_widths: {
                "name" => "420",
                "property_#{property.id}" => "310",
                "property_invalid" => "520",
                "name_invalid" => "999"
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(view.reload.config_json["column_widths"]).to eq(
      "name" => 420,
      "property_#{property.id}" => 310
    )

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    name_col = html.at_css("col[data-column-key='name']")
    property_col = html.at_css("col[data-column-key='property_#{property.id}']")
    expect(name_col).to be_present
    expect(property_col).to be_present
    expect(name_col["style"]).to include("width: 420px")
    expect(property_col["style"]).to include("width: 310px")
  end

  it "clamps resized table column widths to allowed limits" do
    owner = User.create!(email: "database-column-width-clamp-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Column width clamp tables", slug: "column-width-clamp-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Column width clamp DB")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              column_widths: {
                "name" => "20",
                "property_#{property.id}" => "5000"
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(view.reload.config_json["column_widths"]).to eq(
      "name" => 180,
      "property_#{property.id}" => 960
    )
  end

  it "does not render a header eye icon for property visibility" do
    owner = User.create!(email: "database-property-eye-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Property eye tables", slug: "property-eye-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Eye DB")
    DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-db-grid-visibility-toggle")).to be_nil
    expect(response.body).not_to include("Open property visibility")
  end

  it "backfills missing cells so new columns remain editable on existing rows" do
    owner = User.create!(email: "database-backfill-cell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backfill cells tables", slug: "backfill-cells-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Backfill DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Row one")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    cell = DbCell.create!(workspace: workspace, db_row: row, db_property: property, value_text: "")
    cell.destroy!
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    recreated_cell = DbCell.find_by(workspace: workspace, db_row: row, db_property: property)
    expect(recreated_cell).to be_present
    html = Nokogiri::HTML(response.body)
    expect(html.css("input#db_cell_#{recreated_cell.id}_value_text")).not_to be_empty
  end

  it "locks the grid and blocks row edits until unlocked" do
    owner = User.create!(email: "database-lock-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Lock tables", slug: "lock-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Lock DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Initial title")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { locked: true } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.locked).to eq(true)

    get database_path(workspace_slug: workspace.slug, id: database.id, view_settings: "open")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-db-settings-panel is-grid-locked")
    expect(response.body).to include("Grid is locked. Unlock to edit settings.")

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Locked edit" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(row.reload.title).to eq("Initial title")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { name: "Renamed while locked" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.name).to eq("Lock DB")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { locked: false } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.locked).to eq(false)
  end

  it "supports json autosave for database name updates" do
    owner = User.create!(email: "database-name-json-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database name json workspace", slug: "database-name-json-workspace")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Initial grid title")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { name: "Updated grid title" } },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(database.reload.name).to eq("Updated grid title")
    expect(JSON.parse(response.body)).to include(
      "id" => database.id,
      "name" => "Updated grid title"
    )
  end

  it "updates database header controls (icon, description, and cover)" do
    owner = User.create!(email: "database-header-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Header tables", slug: "header-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Header DB")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { icon_action: "set", icon: "🚀" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.icon).to eq("🚀")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { cover_action: "random" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.cover_preset_key).to be_present
    expect(Database::COVER_PRESET_KEYS).to include(database.cover_preset_key)

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { cover_action: "preset", cover_preset_key: "bold-cobalt" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.cover_preset_key).to eq("bold-cobalt")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { cover_shift: "up" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.cover_focal_y).to eq(40)

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("🚀")
    expect(response.body).to include("notae-page-cover")
    expect(response.body).to include("data-controller=\"cover-carousel\"")
    expect(response.body).to include("Original")
    expect(response.body).to include("Vector")
    expect(response.body).to include("Pastel")
    expect(response.body).to include("Bold")
    expect(response.body).to include("Gradient")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { description_action: "set", description: "Tracks launch tasks" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.description).to eq("Tracks launch tasks")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { icon_action: "clear", description_action: "clear", cover_action: "clear" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.icon).to be_nil
    expect(database.reload.description).to be_nil
    expect(database.reload.cover_preset_key).to be_nil
  end

  it "updates row titles inline and normalizes blank titles" do
    owner = User.create!(email: "database-row-update-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row update tables", slug: "row-update-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row update DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Original title")
    database.update_column(:updated_at, 2.days.ago)
    previous_database_updated_at = database.reload.updated_at
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Renamed row" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.reload.title).to eq("Renamed row")
    expect(database.reload.updated_at).to be > previous_database_updated_at

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "   " } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    expect(row.reload.title).to eq("Untitled row")
  end

  it "updates row titles with turbo-stream autosave without full-page redirect" do
    owner = User.create!(email: "database-row-update-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row turbo update tables", slug: "row-turbo-update-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row turbo update DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Original title")
    database.update_column(:updated_at, 2.days.ago)
    previous_database_updated_at = database.reload.updated_at
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Renamed row", autosave_title: "1" } },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="update" target="database_topbar_edited_at"')
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DbRowsController#update")
    expect(row.reload.title).to eq("Renamed row")
    expect(database.reload.updated_at).to be > previous_database_updated_at
  end

  it "creates the next row with turbo streams instead of redirecting the full grid for the simple table path" do
    owner = User.create!(email: "database-row-create-next-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create next turbo tables", slug: "row-create-next-turbo-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create next turbo DB")
    first_row = DbRow.create!(workspace: workspace, database: database, title: "First row")
    second_row = DbRow.create!(workspace: workspace, database: database, title: "Second row")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: first_row.id),
          params: { db_row: { title: "Updated first row", autosave_title: "1", create_next_row: "1" } },
          as: :turbo_stream

    created_row = database.db_rows.where.not(id: [ first_row.id, second_row.id ]).order(:created_at).last
    expect(created_row).to be_present
    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DbRowsController#update")
    expect(response.body).to include('turbo-stream action="replace" target="row_')
    expect(response.body).to include('turbo-stream action="after" target="row_')
    expect(response.body).to include('turbo-stream action="update" target="database_row_count"')
    expect(response.body).to include('turbo-stream action="update" target="database_table_placeholders"')
    expect(response.body).to include('data-auto-submit-focus-on-connect-value="true"')
    expect(response.body).to include("is-new-row-highlight")
    expect(first_row.reload.title).to eq("Updated first row")
    expect(DbRow.for_database(database).active.ordered.pluck(:id)).to eq([ first_row.id, created_row.id, second_row.id ])
  end

  it "creates a new row directly below when row update requests create_next_row" do
    owner = User.create!(email: "database-row-create-next-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create next tables", slug: "row-create-next-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create next DB")
    first_row = DbRow.create!(workspace: workspace, database: database, title: "First row")
    second_row = DbRow.create!(workspace: workspace, database: database, title: "Second row")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: first_row.id),
          params: { db_row: { title: "Updated first row", create_next_row: "1" } }

    created_row = database.db_rows.where.not(id: [ first_row.id, second_row.id ]).order(:created_at).last
    expect(created_row).to be_present
    expect(created_row.title).to eq("Untitled row")
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        anchor: "row_#{created_row.id}",
        highlight_row_id: created_row.id
      )
    )
    expect(first_row.reload.title).to eq("Updated first row")
    expect(DbRow.for_database(database).active.ordered.pluck(:id)).to eq([ first_row.id, created_row.id, second_row.id ])
  end

  it "highlights a newly created untitled row in table view" do
    owner = User.create!(email: "database-row-highlight-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row highlight tables", slug: "row-highlight-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row highlight DB")
    existing_untitled_row = DbRow.create!(workspace: workspace, database: database, title: "Untitled row")
    sign_in owner

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "" } }

    created_row = database.db_rows.where.not(id: existing_untitled_row.id).order(:created_at).last
    expect(created_row).to be_present
    expect(response).to redirect_to(
      database_path(workspace_slug: workspace.slug, id: database.id, highlight_row_id: created_row.id)
    )

    follow_redirect!

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    created_row_node = html.at_css("#row_#{created_row.id}")
    existing_row_node = html.at_css("#row_#{existing_untitled_row.id}")
    expect(created_row_node).to be_present
    expect(existing_row_node).to be_present
    expect(created_row_node["class"]).to include("is-new-row-highlight")
    expect(existing_row_node["class"]).not_to include("is-new-row-highlight")
  end

  it "inserts create-next rows without renumbering unaffected rows when position gaps are available" do
    owner = User.create!(email: "database-row-create-next-position-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create next position tables", slug: "row-create-next-position-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create next position DB")
    first_row = DbRow.create!(workspace: workspace, database: database, title: "First row")
    second_row = DbRow.create!(workspace: workspace, database: database, title: "Second row")
    original_second_position = second_row.position
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: first_row.id),
          params: { db_row: { title: "Updated first row", create_next_row: "1" } }

    created_row = database.db_rows.where.not(id: [ first_row.id, second_row.id ]).order(:created_at).last
    expect(created_row).to be_present
    expect(created_row.position).to be > first_row.reload.position
    expect(created_row.position).to be < second_row.reload.position
    expect(second_row.reload.position).to eq(original_second_position)
  end

  it "closes a row-linked split pane when editing a different row title" do
    owner = User.create!(email: "database-row-split-context-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row split context tables", slug: "row-split-context-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row split context DB")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Linked context page")
    split_row = DbRow.create!(workspace: workspace, database: database, title: "Split row", linked_page: linked_page)
    edited_row = DbRow.create!(workspace: workspace, database: database, title: "Edited row")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: edited_row.id),
          params: {
            db_row: { title: "Edited row updated" },
            split_page_id: linked_page.id,
            split_source: "row",
            split_row_id: split_row.id
          }

    expect(response).to redirect_to(
      database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{edited_row.id}")
    )
    expect(edited_row.reload.title).to eq("Edited row updated")
  end

  it "closes a row-linked split pane when editing a cell in a different row" do
    owner = User.create!(email: "database-cell-split-context-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cell split context tables", slug: "cell-split-context-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Cell split context DB")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Linked split page")
    split_row = DbRow.create!(workspace: workspace, database: database, title: "Split row", linked_page: linked_page)
    edited_row = DbRow.create!(workspace: workspace, database: database, title: "Edited row")
    edited_cell = DbCell.create!(workspace: workspace, db_row: edited_row, db_property: property, value_text: "Todo")
    sign_in owner

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: edited_cell.id),
          params: {
            db_cell: { value_text: "Done" },
            split_page_id: linked_page.id,
            split_source: "row",
            split_row_id: split_row.id
          }

    expect(response).to redirect_to(
      database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{edited_row.id}")
    )
    expect(edited_cell.reload.value_text).to eq("Done")
  end

  it "inserts a newly created row directly below the referenced row" do
    owner = User.create!(email: "database-row-insert-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row insert tables", slug: "row-insert-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row insert DB")
    first_row = DbRow.create!(workspace: workspace, database: database, title: "First")
    second_row = DbRow.create!(workspace: workspace, database: database, title: "Second")
    sign_in owner

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { insert_after_id: first_row.id, db_row: { title: "Inserted" } }

    inserted_row = database.db_rows.find_by!(title: "Inserted")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    ordered_ids = DbRow.for_database(database).active.ordered.pluck(:id)
    expect(ordered_ids).to eq([ first_row.id, inserted_row.id, second_row.id ])
  end

  it "duplicates a row directly underneath and preserves cells, styling, and linked nota" do
    owner = User.create!(email: "database-row-duplicate-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row duplicate tables", slug: "row-duplicate-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row duplicate DB")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Linked note")
    source_row = DbRow.create!(
      workspace: workspace,
      database: database,
      title: "Source row",
      linked_page: linked_page,
      data_json: {
        DbRow::ROW_STYLE_BOLD_KEY => true,
        DbRow::ROW_STYLE_ITALIC_KEY => true,
        DbRow::ROW_STYLE_COLOR_KEY => "purple"
      }
    )
    tail_row = DbRow.create!(workspace: workspace, database: database, title: "Tail row")
    DbCell.create!(workspace: workspace, db_row: source_row, db_property: status_property, value_text: "In progress")
    sign_in owner

    post duplicate_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: source_row.id)

    duplicate_row = database.db_rows.where.not(id: [ source_row.id, tail_row.id ]).find_by!(title: "Source row")
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: linked_page.id,
        split_source: "row",
        split_row_id: duplicate_row.id,
        anchor: "row_#{duplicate_row.id}"
      )
    )
    expect(duplicate_row.linked_page_id).to eq(linked_page.id)
    expect(duplicate_row.row_bold?).to eq(true)
    expect(duplicate_row.row_italic?).to eq(true)
    expect(duplicate_row.row_text_color).to eq("purple")
    expect(duplicate_row.db_cells.find_by!(db_property: status_property).value_text).to eq("In progress")

    ordered_ids = DbRow.for_database(database).active.ordered.pluck(:id)
    expect(ordered_ids).to eq([ source_row.id, duplicate_row.id, tail_row.id ])
  end

  it "updates row style actions and preserves styling after cell sync" do
    owner = User.create!(email: "database-row-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row style tables", slug: "row-style-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row style DB")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Styled row")
    cell = DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "Todo")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { style_action: "toggle_bold" } }
    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { style_action: "toggle_italic" } }
    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { style_action: "set_color", text_color: "blue" } }

    row.reload
    expect(row.row_bold?).to eq(true)
    expect(row.row_italic?).to eq(true)
    expect(row.row_text_color).to eq("blue")

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: cell.id),
          params: { db_cell: { value_text: "Done" } }

    row.reload
    expect(row.row_bold?).to eq(true)
    expect(row.row_italic?).to eq(true)
    expect(row.row_text_color).to eq("blue")
    expect(row.data_json["Status"]).to eq("Done")

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    styled_row = html.at_css("#row_#{row.id}")
    expect(styled_row).to be_present
    expect(styled_row["class"]).to include("is-row-bold")
    expect(styled_row["class"]).to include("is-row-italic")
  end

  it "clears active sorting config when manually reordering rows" do
    owner = User.create!(email: "database-row-manual-order-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Manual order tables", slug: "manual-order-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Manual order DB")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row_one = DbRow.create!(workspace: workspace, database: database, title: "One")
    row_two = DbRow.create!(workspace: workspace, database: database, title: "Two")
    DbCell.create!(workspace: workspace, db_row: row_one, db_property: status_property, value_text: "B")
    DbCell.create!(workspace: workspace, db_row: row_two, db_property: status_property, value_text: "A")
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "sort_property_id" => status_property.id, "sort_direction" => "asc" }
    )
    sign_in owner

    patch move_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row_two.id),
          params: {
            property_id: nil,
            target_value: "",
            target_index: 1,
            view_id: view.id,
            clear_sort: true
          },
          as: :json

    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["redirect_url"]).to include("/w/#{workspace.slug}/databases/#{database.id}")
    expect(payload["redirect_url"]).not_to include("sort_property_id")
    expect(payload["redirect_url"]).not_to include("sort_direction")
    expect(view.reload.config_json).not_to have_key("sort_property_id")
    expect(view.reload.config_json).not_to have_key("sort_direction")
    ordered_ids = DbRow.for_database(database).active.ordered.pluck(:id)
    expect(ordered_ids.last).to eq(row_two.id)
  end

  it "creates and links a page from a row action and opens side peek" do
    owner = User.create!(email: "database-row-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row link tables", slug: "row-link-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row link DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Errol")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { link_action: "create_page" } }

    row.reload
    expect(row.linked_page).to be_present
    expect(row.linked_page.title).to eq("Errol")
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: row.linked_page_id,
        split_source: "row",
        split_row_id: row.id,
        anchor: "row_#{row.id}"
      )
    )

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      split_page_id: row.linked_page_id,
      split_source: "row",
      split_row_id: row.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-db-split-pane")
    expect(response.body).to include("Linked page side peek")
    expect(response.body).to include(row.linked_page.title)
    expect(response.body).to include("Open linked Nota")

    html = Nokogiri::HTML(response.body)
    linked_row = html.at_css("#row_#{row.id}")
    expect(linked_row).to be_present
    expect(linked_row.css(".notae-db-row-link-action").size).to eq(1)
    expect(linked_row.css(".notae-db-row-link-action").first.text.strip).to eq("↗")
    expect(linked_row.css(".notae-db-row-link-chooser")).to be_empty
    expect(linked_row.css(".notae-db-linked-page-row")).to be_empty
    expect(linked_row.css(".notae-db-linked-page-name")).to be_empty
  end

  it "uses the submitted row name when creating a linked page from the name field action" do
    owner = User.create!(email: "database-row-link-name-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row link name tables", slug: "row-link-name-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row link name DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Untitled row")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Webinars", link_action: "create_page" } }

    row.reload
    expect(row.title).to eq("Webinars")
    expect(row.linked_page).to be_present
    expect(row.linked_page.title).to eq("Webinars")
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: row.linked_page_id,
        split_source: "row",
        split_row_id: row.id,
        anchor: "row_#{row.id}"
      )
    )
  end

  it "keeps linked pages attached when editing the row title" do
    owner = User.create!(email: "database-row-edit-linked-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row edit linked tables", slug: "row-edit-linked-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row edit linked DB")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Original linked nota")
    row = DbRow.create!(workspace: workspace, database: database, title: "Old title", linked_page: linked_page)
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { title: "Renamed linked row" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{row.id}"))
    row.reload
    expect(row.title).to eq("Renamed linked row")
    expect(row.linked_page_id).to eq(linked_page.id)

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    linked_row = html.at_css("#row_#{row.id}")
    expect(linked_row).to be_present
    expect(linked_row.at_css("input.notae-db-title-input")).to be_present
    expect(linked_row.css(".notae-db-title-link")).to be_empty
    expect(linked_row.css(".notae-db-row-link-action").size).to eq(1)
    expect(linked_row.css(".notae-db-row-link-action").first.text.strip).to eq("↗")
  end

  it "renders row title editing and linked-nota creation as separate forms" do
    owner = User.create!(email: "database-row-form-separation-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row form separation tables", slug: "row-form-separation-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row form separation DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Draft row")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    row_node = html.at_css("#row_#{row.id}")
    expect(row_node).to be_present

    title_form = row_node.at_css("form.notae-db-title-form-inline")
    expect(title_form).to be_present
    expect(title_form["data-controller"]).to eq("auto-submit")
    expect(title_form["data-turbo"]).to be_nil
    title_input = title_form.at_css("input[name='db_row[title]']")
    expect(title_input).to be_present
    expect(title_input["onkeydown"]).to be_nil
    expect(title_input["data-action"]).to include("change->auto-submit#submit")
    expect(title_input["data-action"]).to include("keydown.enter->auto-submit#submitOnEnter")
    expect(title_input["data-auto-submit-create-next-row-on-enter"]).to eq("true")
    autosave_input = title_form.at_css("input[name='db_row[autosave_title]']")
    expect(autosave_input).to be_present
    expect(autosave_input["value"]).to eq("1")
    create_next_submitter = title_form.at_css("button.notae-db-enter-submitter[name='db_row[create_next_row]'][value='1']")
    expect(create_next_submitter).to be_present
    expect(response.body).not_to include("Create next row")
    expect(title_form.at_css("input[name='db_row[link_action]']")).to be_nil

    create_link_form = row_node.at_css("form.notae-db-row-link-create-form")
    expect(create_link_form).to be_present
    create_link_action_input = create_link_form.at_css("input[name='db_row[link_action]']")
    expect(create_link_action_input).to be_present
    expect(create_link_action_input["value"]).to eq("create_page")
  end

  it "creates and links a row directly from row creation actions" do
    owner = User.create!(email: "database-row-create-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create link tables", slug: "row-create-link-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create link DB")
    existing_page = Page.create!(workspace: workspace, created_by: owner, title: "Existing Nota")
    sign_in owner

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "From create action", link_action: "create_page" } }

    created_row = database.db_rows.find_by!(title: "From create action")
    expect(created_row.linked_page).to be_present
    expect(created_row.linked_page.title).to eq("From create action")
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: created_row.linked_page_id,
        split_source: "row",
        split_row_id: created_row.id
      )
    )

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "From choose action", linked_page_id: existing_page.id } }

    chosen_row = database.db_rows.find_by!(title: "From choose action")
    expect(chosen_row.linked_page_id).to eq(existing_page.id)
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: existing_page.id,
        split_source: "row",
        split_row_id: chosen_row.id
      )
    )
  end

  it "links an existing page to a grid and renders split pane controls" do
    owner = User.create!(email: "database-grid-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid link tables", slug: "grid-link-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Grid link DB")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Linked grid page")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { linked_page_id: linked_page.id } }

    expect(database.reload.linked_page_id).to eq(linked_page.id)
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_page_id: linked_page.id,
        split_source: "database"
      )
    )

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      split_page_id: linked_page.id,
      split_source: "database"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Grid page")
    expect(response.body).not_to include("notae-db-open-link-button")
    expect(response.body).not_to include("Choose page")
    expect(response.body).to include(linked_page.title)
    expect(response.body).to include("Unlink")
    expect(response.body).to include(page_path(workspace_slug: workspace.slug, id: linked_page.id, embedded: 1))
    expect(response.body).not_to include("http://localhost:4000")
  end

  it "keeps the current grid link when an invalid page id is submitted" do
    owner = User.create!(email: "database-grid-link-invalid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid link invalid tables", slug: "grid-link-invalid-tables")
    other_workspace = Workspace.create!(name: "Grid link invalid other", slug: "grid-link-invalid-other")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: other_workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Grid link invalid DB")
    linked_page = Page.create!(workspace: workspace, created_by: owner, title: "Valid linked page")
    remote_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Remote linked page")
    database.update!(linked_page: linked_page)
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { linked_page_id: remote_page.id } }

    expect(database.reload.linked_page_id).to eq(linked_page.id)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
  end

  it "renders pages in embedded shell mode for split-pane previews" do
    owner = User.create!(email: "database-embedded-preview-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded preview tables", slug: "embedded-preview-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Embedded page")
    sign_in owner

    get page_path(workspace_slug: workspace.slug, id: page.id, embedded: 1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-shell-embedded")
    expect(response.body).not_to include("notae-ai-rail")
    expect(response.body).not_to include("notae-topbar-title")
    expect(response.headers["Content-Security-Policy"]).to include("frame-ancestors 'self'")
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
    html = Nokogiri::HTML(response.body)
    active_row_titles = html.css(".notae-db-grid .notae-db-title-input").map { |input| input["value"].to_s.strip }
    expect(active_row_titles).to include("Keep me")
    expect(active_row_titles).not_to include("Archive me")
    expect(kept_row.reload.archived_at).to be_nil
  end

  it "duplicates a grid with properties, rows, values, and views" do
    owner = User.create!(email: "database-duplicate-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Duplicate tables", slug: "duplicate-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Ops grid")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship launch")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "Done")
    DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Board", view_type: :board)
    sign_in owner

    post duplicate_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to be_redirect
    duplicate_id = response.location.split("/").last
    duplicate = Database.find(duplicate_id)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: duplicate.id))
    expect(duplicate.name).to start_with("Ops grid (copy)")

    copied_property = duplicate.db_properties.find_by!(name: "Status")
    copied_row = duplicate.db_rows.find_by!(title: "Ship launch")
    copied_cell = copied_row.db_cells.find_by!(db_property_id: copied_property.id)
    expect(copied_cell.value_text).to eq("Done")
    expect(duplicate.database_views.pluck(:name)).to include("Board")
  end

  it "archives and restores a grid via trash flow" do
    owner = User.create!(email: "database-trash-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database trash tables", slug: "database-trash-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Archive me grid")
    sign_in owner

    patch archive_database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to redirect_to(workspace_trash_path(workspace_slug: workspace.slug))
    expect(database.reload.archived_at).to be_present

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:not_found)

    get workspace_trash_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Archive me grid")

    patch restore_database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.archived_at).to be_nil
  end

  it "restores archived rows from the grid options menu flow" do
    owner = User.create!(email: "database-row-restore-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row restore tables", slug: "row-restore-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row restore grid")
    archived_row = DbRow.create!(workspace: workspace, database: database, title: "Bring me back", archived_at: 1.hour.ago)
    sign_in owner

    patch restore_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: archived_row.id),
          params: { options_menu: "open" }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, options_menu: "open"))
    expect(archived_row.reload.archived_at).to be_nil
  end

  it "exports grid rows as csv" do
    owner = User.create!(email: "database-export-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Export tables", slug: "export-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Export grid")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship launch")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "Done")
    sign_in owner

    get export_csv_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/csv")
    expect(response.body).to include("Name,Status")
    expect(response.body).to include("Ship launch,Done")
  end

  it "toggles small text mode for the grid shell" do
    owner = User.create!(email: "database-small-text-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Small text tables", slug: "small-text-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Small text grid")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { small_text: true } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.small_text).to eq(true)

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    layout_shell = html.at_css(".notae-db-split-layout")
    expect(layout_shell["class"]).to include("is-small-text")
  end

  it "updates grid font style from actions controls" do
    owner = User.create!(email: "database-font-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Font style tables", slug: "font-style-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Font style grid")
    sign_in owner

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { font_style: "serif" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.font_style).to eq("serif")

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    layout_shell = html.at_css(".notae-db-split-layout")
    expect(layout_shell["class"]).to include("is-font-serif")
  end
end
