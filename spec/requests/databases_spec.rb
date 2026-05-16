require "rails_helper"
require "pdf/reader"

RSpec.describe "Databases", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  it "keeps an open tab menu above grid surfaces" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-page-tab-shell:has(.notae-page-tab-menu[open]) {\n  z-index: var(--notae-layer-popover-parent);\n  isolation: isolate;\n}")
    expect(stylesheet).to include(".notae-page-tab-menu {\n  position: static;\n}")
    expect(stylesheet).to include(".notae-page-tab-menu-panel {\n  position: absolute;\n  top: calc(100% + 0.38rem);\n  left: 0;\n  right: auto;")
  end

  it "keeps grid topbar menus above table content" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-viewbar:has(.notae-db-actions-menu[open]),\n.notae-db-viewbar:has(.notae-db-settings-menu[open]) {\n  position: relative;\n  z-index: var(--notae-layer-popover-parent);")
    expect(stylesheet).to include("body.notae-theme-dark .notae-db-actions-menu .notae-actions-panel,\nbody.notae-theme-dark .notae-db-settings-panel,\nbody.notae-theme-dark .notae-db-settings-subpanel {\n  background: var(--notae-surface-raised);\n  backdrop-filter: none;")
    expect(stylesheet).to include("  body.notae-theme-system .notae-db-actions-menu .notae-actions-panel,\n  body.notae-theme-system .notae-db-settings-panel,\n  body.notae-theme-system .notae-db-settings-subpanel {\n    background: var(--notae-surface-raised);\n    backdrop-filter: none;")
  end

  it "keeps uncovered grid pages below the topbar" do
    owner = User.create!(email: "database-standard-surface-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Standard grids", slug: "standard-grids")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Standard grid")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    content = document.at_css("main.notae-content")

    expect(content&.[]("class")).to include("notae-content-page")
    expect(content&.[]("class")).not_to include("notae-content-overlay-page")
  end

  it "keeps covered grid pages in the topbar overlap mode" do
    owner = User.create!(email: "database-cover-surface-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Covered grids", slug: "covered-grids")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(
      workspace: workspace,
      name: "Covered grid",
      cover_preset_key: Database::COVER_PRESET_KEYS.first,
      cover_focal_y: 45
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    content = document.at_css("main.notae-content")

    expect(content&.[]("class")).to include("notae-content-page")
    expect(content&.[]("class")).to include("notae-content-overlay-page")
  end

  it "keeps the board card dialog centered in the viewport" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-board-card-modal[open] {\n  position: fixed;\n  inset: 0;\n  margin: auto;\n}")
  end

  it "keeps grid row creation notices inside the grid canvas instead of the global shell top" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
    template = Rails.root.join("app/views/databases/show.html.erb").read

    expect(stylesheet).to include(".notae-page-inline-flash-host,\n.notae-db-inline-flash-host,")
    expect(stylesheet).to include(".notae-settings-inline-flash-host,\n.notae-auth-flash-host {\n  position: fixed;\n  top: var(--notae-topbar-content-clearance);\n  left: 0;\n  right: 0;\n  z-index: var(--notae-layer-flash);")
    expect(stylesheet).to include(".notae-page-inline-flash-host .notae-flash-stack,\n.notae-db-inline-flash-host .notae-flash-stack,")
    expect(stylesheet).to include(".notae-settings-inline-flash-host .notae-flash-stack,\n.notae-auth-flash-host .notae-flash-stack {\n  width: min(44rem, calc(100% - 1.2rem));")
    expect(template).to include('flash_dom_id: "database_flash_messages"')
    expect(template).to include('flash_host_class: "notae-db-inline-flash-host"')
  end

  it "truncates long board card detail values with ellipsis" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-board-card-detail-value {\n  margin: 0;\n  display: block;\n  flex: 1 1 auto;\n  min-width: 0;\n  overflow: hidden;\n  text-overflow: ellipsis;\n  white-space: nowrap;")
  end

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
    expect(database.linked_page).to be_present
    expect(database.linked_page.title).to eq("Legacy Tasks")
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

  it "offers editable target workspaces in the database options move form" do
    owner = User.create!(email: "database-move-options-owner@example.com", password: "password123")
    source = Workspace.create!(name: "Source move grids", slug: "source-move-grids")
    target = Workspace.create!(name: "Target move grids", slug: "target-move-grids")
    read_only = Workspace.create!(name: "Read only move grids", slug: "read-only-move-grids")
    Membership.create!(workspace: source, user: owner, role: :owner)
    Membership.create!(workspace: target, user: owner, role: :member)
    Membership.create!(workspace: read_only, user: owner, role: :auditor)
    database = Database.create!(workspace: source, created_by: owner, name: "Moveable grid")
    sign_in owner

    get panel_database_path(workspace_slug: source.slug, id: database.id, panel: "options")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Move")
    expect(response.body).to include(target.name)
    expect(response.body).not_to include(read_only.name)
    expect(response.body).to include(move_workspace_database_path(workspace_slug: source.slug, id: database.id))
  end

  it "moves a grid and its direct content to another workspace" do
    owner = User.create!(email: "database-move-owner@example.com", password: "password123")
    source = Workspace.create!(name: "Source moved grid", slug: "source-moved-grid")
    target = Workspace.create!(name: "Target moved grid", slug: "target-moved-grid")
    Membership.create!(workspace: source, user: owner, role: :owner)
    Membership.create!(workspace: target, user: owner, role: :owner)
    linked_page = Page.create!(workspace: source, created_by: owner, title: "Grid shell")
    external_page = Page.create!(workspace: source, created_by: owner, title: "External row note")
    database = Database.create!(workspace: source, created_by: owner, name: "Move this grid", linked_page: linked_page)
    property = DbProperty.create!(workspace: source, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: source, database: database, title: "Task", linked_page: external_page)
    cell = DbCell.create!(workspace: source, db_row: row, db_property: property, value_text: "Started")
    view = DatabaseView.create!(workspace: source, database: database, created_by: owner, name: "Table", view_type: :table)
    comment = Comment.create!(workspace: source, commentable: database, author: owner, body: "Move this grid comment")
    share_link = DatabaseShareLink.create!(workspace: source, database: database, created_by: owner)
    favorite = Favorite.create!(workspace: source, user: owner, favoritable: database)
    sign_in owner

    patch move_workspace_database_path(workspace_slug: source.slug, id: database.id),
          params: { target_workspace_id: target.id }

    expect(response).to redirect_to(database_path(workspace_slug: target.slug, id: database.id))
    expect(database.reload.workspace).to eq(target)
    expect(linked_page.reload.workspace).to eq(target)
    expect(external_page.reload.workspace).to eq(source)
    expect(property.reload.workspace).to eq(target)
    expect(row.reload.workspace).to eq(target)
    expect(row.linked_page_id).to be_nil
    expect(cell.reload.workspace).to eq(target)
    expect(view.reload.workspace).to eq(target)
    expect(comment.reload.workspace).to eq(target)
    expect(share_link.reload.workspace).to eq(target)
    expect(favorite.reload.workspace).to eq(target)
    expect(AuditEvent.where(workspace: target, auditable: database, action: "move")).to exist
  end

  it "does not move a grid when its linked nota is hidden from the actor" do
    owner = User.create!(email: "database-move-hidden-owner@example.com", password: "password123")
    member = User.create!(email: "database-move-hidden-member@example.com", password: "password123")
    source = Workspace.create!(name: "Source hidden moved grid", slug: "source-hidden-moved-grid")
    target = Workspace.create!(name: "Target hidden moved grid", slug: "target-hidden-moved-grid")
    Membership.create!(workspace: source, user: owner, role: :owner)
    Membership.create!(workspace: source, user: member, role: :member)
    Membership.create!(workspace: target, user: member, role: :member)
    hidden_linked_page = Page.create!(
      workspace: source,
      created_by: owner,
      title: "Private grid shell",
      permission_mode: :private_page
    )
    database = Database.create!(workspace: source, created_by: owner, name: "Shared grid", linked_page: hidden_linked_page)
    row = DbRow.create!(workspace: source, database: database, title: "Task")
    sign_in member

    expect do
      patch move_workspace_database_path(workspace_slug: source.slug, id: database.id),
            params: { target_workspace_id: target.id }
    end.not_to change { [ database.reload.workspace_id, hidden_linked_page.reload.workspace_id, row.reload.workspace_id ] }

    expect(response).to redirect_to(database_path(workspace_slug: source.slug, id: database.id))
    expect(flash[:alert]).to eq("Cannot move documents you do not have access to.")
    expect(AuditEvent.where(workspace: target, auditable: database, action: "move")).not_to exist
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

  it "turns the current blank grid into a tasks grid instead of creating a new database" do
    owner = User.create!(email: "database-taskify-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Taskify tables", slug: "taskify-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Planning")
    row = DbRow.create!(workspace: workspace, database: database, title: "Existing row")
    sign_in owner

    expect do
      post taskify_database_path(workspace_slug: workspace.slug, id: database.id)
    end.not_to change(Database, :count)

    database.reload
    table_view = database.database_views.find_by!(view_type: :table)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: table_view.id))
    expect(database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Status", "select" ],
        [ "Date created", "date" ],
        [ "Due date", "date" ],
        [ "Notes", "text" ]
      ]
    )

    status_property = database.db_properties.find_by!(name: "Status")
    date_created_property = database.db_properties.find_by!(name: "Date created")
    expect(row.db_cells.find_by!(db_property: status_property).value_text).to eq("not started")
    expect(row.db_cells.find_by!(db_property: date_created_property).value_text).to eq(row.created_at.to_date.iso8601)
    expect(Array(table_view.reload.config_json["visible_property_ids"]).map(&:to_s)).to eq(
      database.db_properties.order(:position).pluck(:id).map(&:to_s)
    )
  end

  it "turns a blank grid into a stats grid with setup rows and period entry rows" do
    owner = User.create!(email: "database-stats-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stats tables", slug: "stats-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    sign_in owner

    expect do
      post statsify_database_path(workspace_slug: workspace.slug, id: database.id)
    end.not_to change(Database, :count)

    database.reload
    table_view = database.database_views.find_by!(view_type: :table)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: table_view.id, stats_mode: "setup"))
    expect(database.applied_template_name).to eq("Stats")
    expect(database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Frequency", "select" ],
        [ "Assigned person", "text" ],
        [ "Post", "text" ],
        [ "Division", "text" ],
        [ "Description", "text" ],
        [ "Period start", "date" ],
        [ "Period label", "text" ],
        [ "Value", "number" ]
      ]
    )

    patch stats_setup_database_path(workspace_slug: workspace.slug, id: database.id),
          params: {
            stats_date: "2026-05-15",
            stats: {
              new_definition: {
                title: "Subscriber count",
                frequency: "weekly_thu_2pm",
                assigned_person: "Errol",
                post: "Publisher",
                division: "Marketing",
                description: "Total active subscribers"
              }
            }
          }

    definition = database.db_rows.find_by!(title: "Subscriber count")
    expect(definition.data_json[Databases::StatsTemplateService::ROW_TYPE_KEY]).to eq(Databases::StatsTemplateService::ROW_TYPE_DEFINITION)
    expect(definition.data_json[Databases::StatsTemplateService::FREQUENCY_KEY]).to eq("weekly_thu_2pm")
    expect(definition.db_cells.joins(:db_property).find_by!(db_properties: { name: "Assigned person" }).value_text).to eq("Errol")
    expect(definition.db_cells.joins(:db_property).find_by!(db_properties: { name: "Division" }).value_text).to eq("Marketing")
    expect(definition.db_cells.joins(:db_property).find_by!(db_properties: { name: "Description" }).value_text).to eq("Total active subscribers")

    get database_path(workspace_slug: workspace.slug, id: database.id, stats_mode: "setup", stats_date: "2026-05-15")

    expect(response).to have_http_status(:ok)
    setup_html = Nokogiri::HTML(response.body)
    setup_row = setup_html.at_css("#stats_definition_#{definition.id}")
    expect(setup_html.text).to include("Division", "Description")
    expect(setup_html.at_css("button[name='add_definition'][value='1']").text.squish).to eq("+ New row")
    expect(setup_html.at_css(".notae-db-stats-savebar .notae-db-toolbar-new").text.squish).to eq("Save setup")
    expect(setup_html.at_css("#stats_setup_rows")["data-controller"]).to include("db-table-reorder")
    expect(setup_row.at_css(".notae-db-row-more-menu")).to be_present
    expect(setup_row.at_css(".notae-db-row-more-menu")["data-row-menu-url-value"]).to be_blank
    expect(setup_row.css(".notae-db-row-menu-section-label").map { |node| node.text.squish }).to include("Text colour", "Background colour")
    expect(
      setup_row.css(".notae-db-row-menu-form").find { |form| form.at_css("input[name='db_row[style_action]'][value='set_color']") }["data-turbo"]
    ).to eq("false")
    expect(setup_row.at_css(".is-drag-handle")).to be_present
    expect(setup_row.at_css("input[name='stats[definitions][#{definition.id}][title]']")["data-action"]).to include(
      "change->stats-setup#save",
      "keydown.enter->stats-setup#insertAfter"
    )
    expect(setup_row.at_css("select[name='stats[definitions][#{definition.id}][frequency]']")["data-action"]).to include("change->stats-setup#save")
    expect(setup_row.at_css("input[name='stats[definitions][#{definition.id}][assigned_person]']")["data-action"]).to include("change->stats-setup#save")
    expect(setup_row.at_css("input[name='stats[definitions][#{definition.id}][post]']")["data-action"]).to include("change->stats-setup#save")
    expect(setup_row.at_css("input[name='stats[definitions][#{definition.id}][division]']")["data-action"]).to include("change->stats-setup#save")
    expect(setup_row.at_css("input[name='stats[definitions][#{definition.id}][description]']")["data-action"]).to include("change->stats-setup#save")

    patch stats_setup_database_path(workspace_slug: workspace.slug, id: database.id),
          params: {
            stats_date: "2026-05-15",
            add_definition_after_id: definition.id,
            stats: {
              definitions: {
                definition.id => {
                  title: "Subscriber count",
                  frequency: "weekly_thu_2pm",
                  assigned_person: "Errol",
                  post: "Publisher",
                  division: "Marketing",
                  description: "Total active subscribers"
                }
              }
            }
          }

    added_definition = database.db_rows.where(title: "Untitled stat").order(:created_at).last
    expect(added_definition).to be_present
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        stats_mode: "setup",
        stats_date: "2026-05-15",
        anchor: "stats_definition_#{added_definition.id}"
      )
    )
    expect(database.db_rows.active.ordered.pluck(:id)).to eq([ definition.id, added_definition.id ])

    patch stats_entries_database_path(workspace_slug: workspace.slug, id: database.id),
          params: {
            stats_date: "2026-05-15",
            stats: {
              entries: {
                definition.id => { value: "42" }
              }
            }
          }

    entry = database.db_rows.where("data_json ->> ? = ?", Databases::StatsTemplateService::ROW_TYPE_KEY, Databases::StatsTemplateService::ROW_TYPE_ENTRY).first
    expect(entry).to be_present
    expect(entry.data_json[Databases::StatsTemplateService::DEFINITION_ID_KEY]).to eq(definition.id)
    expect(entry.data_json[Databases::StatsTemplateService::PERIOD_START_KEY]).to eq("2026-05-14")
    expect(entry.db_cells.joins(:db_property).find_by!(db_properties: { name: "Value" }).value_text).to eq("42")

    get database_path(workspace_slug: workspace.slug, id: database.id, stats_date: "2026-05-15")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subscriber count")
    expect(response.body).to include("14 May 2026 2pm - 21 May 2026 2pm")
    expect(response.body).to include("value=\"42\"")
    expect(response.body).to include("Show graph")
  end

  it "archives stats definitions without deleting historical stat reports" do
    owner = User.create!(email: "database-stats-archive-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stats archive", slug: "stats-archive")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    sign_in owner

    post statsify_database_path(workspace_slug: workspace.slug, id: database.id)
    patch stats_setup_database_path(workspace_slug: workspace.slug, id: database.id),
          params: {
            stats_date: "2026-05-15",
            stats: {
              new_definition: {
                title: "Revenue",
                frequency: "weekly_mon_sun",
                assigned_person: "Ari",
                post: "Ops"
              }
            }
          }
    definition = database.db_rows.find_by!(title: "Revenue")
    patch stats_entries_database_path(workspace_slug: workspace.slug, id: database.id),
          params: {
            stats_date: "2026-05-15",
            stats: { entries: { definition.id => { value: "1200" } } }
          }

    expect do
      patch stats_setup_database_path(workspace_slug: workspace.slug, id: database.id),
            params: {
              stats_date: "2026-05-15",
              archive_stat_id: definition.id,
              stats: {
                definitions: {
                  definition.id => {
                    title: "Revenue",
                    frequency: "weekly_mon_sun",
                    assigned_person: "Ari",
                    post: "Ops",
                    division: "Finance",
                    description: "Weekly booked revenue"
                  }
                }
              }
            }
    end.not_to change { database.db_rows.count }

    expect(definition.reload).to be_archived
    get database_path(workspace_slug: workspace.slug, id: database.id, stats_date: "2026-05-15")

    expect(response.body).to include("Revenue")
    expect(response.body).to include("value=\"1200\"")
  end

  it "upgrades a kanban starter grid into a tasks grid on the same database" do
    owner = User.create!(email: "database-taskify-kanban-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Taskify kanban tables", slug: "taskify-kanban-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Sprint board")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    post kanbanize_database_path(workspace_slug: workspace.slug, id: database.id)
    board_view = database.reload.database_views.find_by!(view_type: :board)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id))

    expect do
      post taskify_database_path(workspace_slug: workspace.slug, id: database.id)
    end.not_to change(Database, :count)

    database.reload
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: database.database_views.find_by!(view_type: :table).id))
    expect(database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Status", "select" ],
        [ "Date created", "date" ],
        [ "Due date", "date" ],
        [ "Notes", "text" ]
      ]
    )

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    view_options = document.css(".notae-db-split-view-menu .notae-db-split-view-panel").last.css(".notae-db-split-view-option")
    default_option = view_options.first

    expect(default_option.text.squish).to eq("Default")
    expect(default_option["href"]).to include("view_id=#{database.database_views.find_by!(view_type: :table).id}")
  end

  it "saves a grid template, reapplies it, and renders the new template toolbar" do
    owner = User.create!(email: "database-template-toolbar-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Template toolbar tables", slug: "template-toolbar-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    source_database = Database.create!(workspace: workspace, created_by: owner, name: "Source grid")
    status_property = DbProperty.create!(workspace: workspace, database: source_database, name: "Status", property_type: :select, position: 1024)
    due_date_property = DbProperty.create!(workspace: workspace, database: source_database, name: "Due date", property_type: :date, position: 2048)
    source_view = DatabaseView.create!(
      workspace: workspace,
      database: source_database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: {
        "visible_property_ids" => [ status_property.id, due_date_property.id ],
        "sort_property_id" => due_date_property.id,
        "sort_direction" => "asc"
      }
    )
    target_database = Database.create!(workspace: workspace, created_by: owner, name: "Target grid")
    sign_in owner

    post save_as_template_database_path(workspace_slug: workspace.slug, id: source_database.id),
         params: {
           view_id: source_view.id,
           database_template: { name: "Project tracker" }
         }

    template = DatabaseTemplate.find_by!(workspace: workspace, name: "Project tracker")
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: source_database.id, view_id: source_view.id))
    expect(template.snapshot_json.dig("view", "config_json", "sort_property_name")).to eq("Due date")

    post apply_template_database_path(workspace_slug: workspace.slug, id: target_database.id),
         params: { template_id: template.id }

    target_database.reload
    expect(response).to redirect_to(/\/w\/#{workspace.slug}\/databases\/#{target_database.id}/)
    expect(target_database.applied_template_name).to eq("Project tracker")
    expect(target_database.database_template).to eq(template)
    expect(target_database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Status", "select" ],
        [ "Due date", "date" ]
      ]
    )

    get database_path(workspace_slug: workspace.slug, id: target_database.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    toolbar_label = document.at_css(".notae-db-viewbar-left .notae-db-view-pill")
    toolbar_summaries = document.css(".notae-db-template-actions details > summary").map { |node| node.text.squish }
    templates_panel_text = document.css(".notae-db-template-actions .notae-db-split-view-panel").first&.text.to_s

    expect(toolbar_label&.text.to_s).to include("Project tracker")
    expect(toolbar_summaries).to include("Templates ▾", "Views ▾")
    expect(document.css(".notae-db-template-actions > form > button").map { |node| node.text.squish }).not_to include("Grid")
    expect(templates_panel_text).to include("Tasks")
    expect(templates_panel_text).to include("Project tracker")
    expect(templates_panel_text).to include("Save current layout")
    expect(templates_panel_text).to include("Save as template")
  end

  it "renders and updates dropdown property options from the column menu" do
    owner = User.create!(email: "database-dropdown-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Dropdown tables", slug: "dropdown-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Dropdown grid")
    property = DbProperty.create!(
      workspace: workspace,
      database: database,
      name: "Priority",
      property_type: :select,
      select_options_json: [ "High" ]
    )
    row = DbRow.create!(workspace: workspace, database: database, title: "Task one")
    DbCell.create!(workspace: workspace, db_row: row, db_property: property, value_text: "High")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    property_type_labels = document.css("select[name='db_property[property_type]'] option").map(&:text)

    expect(property_type_labels).to include("Dropdown")
    expect(response.body).not_to include('data-turbo-confirm="Are you sure?"')

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "column_menu", property_id: property.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add dropdown item")
    expect(response.body).to include("High")
    expect(response.body).to include('data-turbo-confirm="Are you sure?"')

    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: property.id),
          params: {
            db_property: {
              select_option_action: "add_select_option",
              select_option_value: "Low"
            }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(property.reload.select_options_list).to eq([ "High", "Low" ])

    get database_path(workspace_slug: workspace.slug, id: database.id)

    document = Nokogiri::HTML(response.body)
    dropdown = document.at_css("select.notae-db-cell-input")
    expect(dropdown.css("option").map { |option| option["value"] }).to include("", "High", "Low")

    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: property.id),
          params: {
            db_property: {
              select_option_action: "remove_select_option",
              select_option_value: "High"
            }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(property.reload.select_options_list).to eq([ "Low" ])
  end

  it "creates a dropdown property with configured options from the add-property form" do
    owner = User.create!(email: "database-dropdown-create-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Dropdown create tables", slug: "dropdown-create-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Task board")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="dropdown-property-form"')
    expect(response.body).to include('data-dropdown-property-form-target="draftInput"')

    post database_db_properties_path(workspace_slug: workspace.slug, database_id: database.id),
         params: {
           db_property: {
             name: "Priority",
             property_type: "select",
             select_options_json: [ "High", "Low", "Medium" ]
           }
         }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    property = database.db_properties.find_by!(name: "Priority")
    expect(property.select_options_list).to eq([ "High", "Low", "Medium" ])
  end

  it "disables taskify for custom grids and rejects direct taskify requests" do
    owner = User.create!(email: "database-taskify-custom-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Taskify custom tables", slug: "taskify-custom-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Custom grid")
    DbProperty.create!(workspace: workspace, database: database, name: "Priority", property_type: :text)
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    tasks_button = html.at_css("form[action='#{taskify_database_path(workspace_slug: workspace.slug, id: database.id)}'] button")
    expect(tasks_button).to be_present
    expect(tasks_button["disabled"]).to be_present

    post taskify_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(flash[:alert]).to eq("This grid already has custom fields. Open a blank grid or new tab before using the Tasks template.")
    expect(database.reload.db_properties.order(:position).pluck(:name, :property_type)).to eq([ [ "Priority", "text" ] ])
  end

  it "renders linked tabs under the parent page title for a tabbed grid" do
    owner = User.create!(email: "database-tabs-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database tabs", slug: "database-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Operations")
    note_tab = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Summary")
    grid_tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Tasks anchor")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Tasks Grid", linked_page: grid_tab_page)
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    labels = html.css(".notae-page-tabs .notae-page-tab-label").map(&:text).map(&:strip)
    active_link = html.at_css(".notae-page-tabs .notae-page-tab.is-active .notae-page-tab-label")
    title_input = html.at_css(".notae-page-title-input")

    expect(labels).to eq([ "Tab 1", note_tab.title, grid_tab_page.title ])
    expect(active_link).to be_present
    expect(active_link.text.strip).to eq(grid_tab_page.title)
    expect(html.css(".notae-page-tab-icon")).to be_empty
    expect(title_input.text.strip).to eq(group_page.title)
    expect(html.at_css(%(.notae-page-tab[href="#{page_path(workspace_slug: workspace.slug, id: group_page.id)}"]))).to be_present
    expect(html.at_css(%(.notae-page-tab[href="#{page_path(workspace_slug: workspace.slug, id: note_tab.id)}"]))).to be_present
    expect(html.at_css(%(.notae-page-tab[href="#{database_path(workspace_slug: workspace.slug, id: database.id)}"]))).to be_present
    expect(html.at_css(".notae-page-tab-create-form input[name='quick_create']")["value"]).to eq("1")
    expect(html.at_css(".notae-page-tab-create-form input[name='database[parent_page_id]']")["value"]).to eq(group_page.id)
    expect(html.at_css(".notae-page-tab-create-form input[name='database[tab_title]']")["value"]).to eq("New tab")
  end

  it "backfills a shell page for an existing top-level grid and shows its default tab" do
    owner = User.create!(email: "database-default-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database default tabs", slug: "database-default-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Original grid")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(database.reload.linked_page).to be_present
    html = Nokogiri::HTML(response.body)
    labels = html.css(".notae-page-tabs .notae-page-tab-label").map(&:text).map(&:strip)
    active_link = html.at_css(%(.notae-page-tab.is-active[href="#{database_path(workspace_slug: workspace.slug, id: database.id)}"]))

    expect(labels).to eq([ "Tab 1" ])
    expect(active_link).to be_present
    expect(html.at_css(".notae-page-tab-create-form input[name='quick_create']")["value"]).to eq("1")
    expect(html.at_css(".notae-page-tab-create-form input[name='database[parent_page_id]']")["value"]).to eq(database.linked_page.id)
    expect(html.at_css(".notae-page-tab-create-form input[name='database[tab_title]']")["value"]).to eq("New tab")
  end

  it "renames the first grid tab without changing the document title" do
    owner = User.create!(email: "database-root-tab-rename-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database root tab rename", slug: "database-root-tab-rename")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Planning grid")
    Databases::EnsureLinkedPageService.call(database: database, actor: owner)
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: database.linked_page.id),
          params: {
            return_to: database_path(workspace_slug: workspace.slug, id: database.id),
            page: { root_tab_title: "Execution" }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.linked_page.reload.title).to eq("Planning grid")
    expect(database.linked_page.root_tab_title).to eq("Execution")

    get database_path(workspace_slug: workspace.slug, id: database.id)

    html = Nokogiri::HTML(response.body)
    expect(html.css(".notae-page-tab-label").map(&:text).map(&:strip)).to eq([ "Execution" ])
    expect(html.at_css(".notae-page-title-input")&.text&.strip).to eq("Planning grid")
  end

  it "keeps the parent shell visible for a tabbed grid while shifting the content context" do
    owner = User.create!(email: "database-shell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database shell", slug: "database-shell")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Planning",
      icon: "🚀",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )
    Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Notes")
    grid_tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Execution")
    database = Database.create!(
      workspace: workspace,
      created_by: owner,
      name: "Execution grid",
      description: "Grid-specific description",
      linked_page: grid_tab_page
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-page-title-input")&.text&.strip).to eq(group_page.title)
    expect(html.at_css(".notae-page-icon-display")&.text&.strip).to eq(group_page.icon)
    expect(html.at_css(".notae-page-cover-preset")).to be_present
    expect(html.at_css(".notae-db-description")).to be_nil
    expect(html.css(".notae-page-tab-label").map(&:text).map(&:strip)).to eq([ "Tab 1", "Notes", grid_tab_page.title ])
    expect(html.at_css(%(.notae-page-tab.is-active[href="#{database_path(workspace_slug: workspace.slug, id: database.id)}"]))).to be_present
  end

  it "renames and recolors a grid tab without detaching it from the parent page" do
    owner = User.create!(email: "database-rename-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database rename tabs", slug: "database-rename-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(workspace: workspace, created_by: owner, title: "Finance")
    linked_tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Forecast")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Forecast grid", linked_page: linked_tab_page)
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: linked_tab_page.id),
          params: {
            return_to: database_path(workspace_slug: workspace.slug, id: database.id),
            page: { title: "Approved forecast", tab_color: "blue" }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(linked_tab_page.reload.title).to eq("Approved forecast")
    expect(linked_tab_page.tab_color).to eq("blue")
    expect(linked_tab_page.parent_page_id).to eq(group_page.id)
  end

  it "creates a new grid tab under the same parent shell instead of a blank nota" do
    owner = User.create!(email: "database-new-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database new tabs", slug: "database-new-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    group_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Roadmap",
      icon: "🚀",
      cover_preset_key: Page::COVER_PRESET_KEYS.first
    )
    linked_tab_page = Page.create!(workspace: workspace, parent_page: group_page, created_by: owner, title: "Current sprint")
    existing_database = Database.create!(workspace: workspace, created_by: owner, name: "Sprint grid", linked_page: linked_tab_page)
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: {
           database: {
             name: "Untitled grid",
             parent_page_id: group_page.id,
             tab_title: "New tab"
           }
         }

    created_database = workspace.databases.order(:created_at).last

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: created_database.id))
    expect(created_database).not_to eq(existing_database)
    expect(created_database.linked_page).to be_present
    expect(created_database.linked_page.parent_page_id).to eq(group_page.id)
    expect(created_database.linked_page.title).to eq("New tab")
    expect(created_database.linked_page.icon).to eq(group_page.icon)
    expect(created_database.linked_page.cover_preset_key).to eq(group_page.cover_preset_key)
    expect(created_database.name).to eq("Untitled grid")
  end

  it "preserves the parent grid title and cover when a new grid tab is converted to tasks" do
    owner = User.create!(email: "database-task-tab-shell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database task tab shell", slug: "database-task-tab-shell")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    root_database = Database.create!(
      workspace: workspace,
      created_by: owner,
      name: "Client rollout",
      icon: "🚀",
      cover_preset_key: Database::COVER_PRESET_KEYS.first,
      cover_focal_y: 35
    )
    root_shell = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Client rollout",
      icon: nil,
      cover_preset_key: nil,
      cover_focal_y: 50
    )
    root_database.update!(linked_page: root_shell)
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: {
           database: {
             name: "Untitled grid",
             parent_page_id: root_shell.id,
             tab_title: "Tasks"
           }
         }

    task_tab_database = workspace.databases.order(:created_at).last
    post taskify_database_path(workspace_slug: workspace.slug, id: task_tab_database.id)

    table_view = task_tab_database.reload.database_views.find_by!(view_type: :table)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: task_tab_database.id, view_id: table_view.id))
    expect(root_shell.reload.title).to eq("Client rollout")
    expect(root_shell.icon).to eq("🚀")
    expect(root_shell.cover_preset_key).to eq(root_database.cover_preset_key)
    expect(task_tab_database.linked_page.title).to eq("Tasks")

    get database_path(workspace_slug: workspace.slug, id: task_tab_database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css(".notae-page-title-input")&.text&.strip).to eq("Client rollout")
    expect(html.at_css(".notae-page-cover-preset")).to be_present
    expect(html.css(".notae-page-tab-label").map(&:text).map(&:strip)).to include("Tasks")
  end

  it "creates a new top-level grid tab without falling back home when the default name already exists" do
    owner = User.create!(email: "database-top-level-tab-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database top level tabs", slug: "database-top-level-tabs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Planning grid")
    Databases::EnsureLinkedPageService.call(database: database, actor: owner)
    Database.create!(workspace: workspace, created_by: owner, name: "Untitled grid")
    sign_in owner

    post databases_path(workspace_slug: workspace.slug),
         params: {
           quick_create: "1",
           database: {
             name: "Untitled grid",
             parent_page_id: database.linked_page.id,
             tab_title: "New tab"
           }
         }

    created_database = workspace.databases.order(:created_at).last

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: created_database.id))
    expect(created_database).not_to eq(database)
    expect(created_database.name).to eq("Untitled grid 2")
    expect(created_database.linked_page).to be_present
    expect(created_database.linked_page.parent_page_id).to eq(database.linked_page.id)
    expect(created_database.linked_page.title).to eq("New tab")
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
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    db_row = DbRow.create!(workspace: workspace, database: database, title: "Inline row")
    db_cell = DbCell.create!(workspace: workspace, db_row: db_row, db_property: db_property, value_text: "started")
    database.update_column(:updated_at, 2.days.ago)
    previous_database_updated_at = database.reload.updated_at
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/db_cells/#{db_cell.id}")
    expect(response.body).to include('data-auto-submit-method="patch"')
    expect(response.body).to include('data-auto-submit-param-name="db_cell[value_text]"')

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: db_cell.id),
          params: { db_cell: { value_text: "done" } },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="update" target="database_topbar_edited_at"')
    expect(response.body).to include(%(turbo-stream action="replace" target="row_#{db_row.id}"))
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include("Cell updated.")
    expect(response.body).to include("Edited")
    expect(response.body).to include("is-row-color-gray")
    expect(response.body).to include("is-status-done")
    expect(db_cell.reload.value_text).to eq("done")
    expect(db_row.reload.data_json["Status"]).to eq("done")
    expect(db_row.reload.row_text_color).to eq("gray")
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

  it "renames a column from the grid header" do
    owner = User.create!(email: "database-rename-column-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Rename", slug: "tables-rename")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Compnay", property_type: :text)
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
    column_menu = html.at_css("th[data-column-key='property_#{db_property.id}'] .notae-db-column-hover-controls")
    expect(column_menu).to be_present
    expect(column_menu["data-row-menu-url-value"]).to include("panels/column_menu")
    expect(column_menu["data-row-menu-url-value"]).to include("property_id=#{db_property.id}")
    expect(response.body).not_to include("Rename Compnay column")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "column_menu", property_id: db_property.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    panel_html = Nokogiri::HTML.fragment(response.body)
    rename_form = panel_html.at_css("form[action='#{database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id, view_id: view.id)}']")
    expect(rename_form).to be_present
    expect(rename_form.at_css("input[name='db_property[name]']")["value"]).to eq("Compnay")
    expect(response.body).to include("Rename Compnay column")

    patch database_db_property_path(
            workspace_slug: workspace.slug,
            database_id: database.id,
            id: db_property.id,
            view_id: view.id,
            sort_property_id: db_property.id,
            sort_direction: "asc",
            sort_mode: "calendar"
          ),
          params: { db_property: { name: "Company" } }

    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        view_id: view.id,
        sort_property_id: db_property.id,
        sort_direction: "asc",
        sort_mode: "calendar"
      )
    )
    expect(db_property.reload.name).to eq("Company")
  end

  it "renders a hover column menu and applies column style actions" do
    owner = User.create!(email: "database-column-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Column Style", slug: "tables-column-style")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    db_property = DbProperty.create!(workspace: workspace, database: database, name: "Priority", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Q1")
    DbCell.create!(workspace: workspace, db_row: row, db_property: db_property, value_text: "High")
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
    column_header = html.at_css("th[data-column-key='property_#{db_property.id}']")
    expect(column_header).to be_present
    expect(column_header.at_css(".notae-db-column-hover-controls")).to be_present
    expect(column_header.at_css("[aria-label='Column options for Priority']")).to be_present
    expect(column_header.at_css(".notae-db-grid-property-edit")).to be_nil
    column_menu = column_header.at_css(".notae-db-column-hover-controls")
    expect(column_menu["data-row-menu-url-value"]).to include("panels/column_menu")
    expect(column_menu["data-row-menu-url-value"]).to include("property_id=#{db_property.id}")
    expect(column_menu.css("form")).to be_empty
    expect(response.body).not_to include("Rename Priority column")
    expect(response.body).not_to include("Bold column")
    expect(response.body).not_to include("Background colour")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "column_menu", property_id: db_property.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rename Priority column")
    expect(response.body).to include("Bold column")
    expect(response.body).to include("Italic column")
    expect(response.body).to include("Background colour")

    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id, view_id: view.id),
          params: { db_property: { style_action: "toggle_bold" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id))

    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id, view_id: view.id),
          params: { db_property: { style_action: "toggle_italic" } }
    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id, view_id: view.id),
          params: { db_property: { style_action: "set_color", text_color: "blue" } }
    patch database_db_property_path(workspace_slug: workspace.slug, database_id: database.id, id: db_property.id, view_id: view.id),
          params: { db_property: { style_action: "set_background_color", background_color: "mint" } }

    db_property.reload
    expect(db_property.column_bold?).to eq(true)
    expect(db_property.column_italic?).to eq(true)
    expect(db_property.column_text_color).to eq("blue")
    expect(db_property.column_background_color).to eq("mint")

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    column_header = html.at_css("th[data-column-key='property_#{db_property.id}']")
    expect(column_header["class"]).to include("is-column-bold")
    expect(column_header["class"]).to include("is-column-italic")
    expect(column_header["class"]).to include("is-column-color-blue")
    expect(column_header["class"]).to include("is-column-bg-mint")

    styled_cell = html.at_css("#row_#{row.id} td.is-column-color-blue.is-column-bg-mint")
    expect(styled_cell).to be_present
    expect(styled_cell["class"]).to include("is-column-bold")
    expect(styled_cell["class"]).to include("is-column-italic")
  end

  it "renders a hover menu for the name column and applies name column style actions" do
    owner = User.create!(email: "database-name-column-style-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Name Column Style", slug: "tables-name-column-style")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    row = DbRow.create!(workspace: workspace, database: database, title: "Q1")
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
    name_header = html.at_css("th[data-column-key='name']")
    expect(name_header).to be_present
    expect(name_header.at_css(".notae-db-column-hover-controls")).to be_present
    expect(name_header.at_css("[aria-label='Column options for Name']")).to be_present
    name_menu = name_header.at_css(".notae-db-column-hover-controls")
    expect(name_menu["data-row-menu-url-value"]).to include("panels/name_column_menu")
    expect(name_menu.css("form")).to be_empty
    expect(response.body).not_to include("Bold column")
    expect(response.body).not_to include("Background colour")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "name_column_menu", view_id: view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bold column")
    expect(response.body).to include("Italic column")
    expect(response.body).to include("Background colour")

    patch database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id),
          params: { database: { style_action: "toggle_bold" } }
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id))

    patch database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id),
          params: { database: { style_action: "toggle_italic" } }
    patch database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id),
          params: { database: { style_action: "set_color", text_color: "purple" } }
    patch database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id),
          params: { database: { style_action: "set_background_color", background_color: "rose" } }

    database.reload
    expect(database.name_column_text_bold?).to eq(true)
    expect(database.name_column_text_italic?).to eq(true)
    expect(database.name_column_text_color).to eq("purple")
    expect(database.name_column_background_color).to eq("rose")

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    name_header = html.at_css("th[data-column-key='name']")
    expect(name_header["class"]).to include("is-column-bold")
    expect(name_header["class"]).to include("is-column-italic")
    expect(name_header["class"]).to include("is-column-color-purple")
    expect(name_header["class"]).to include("is-column-bg-rose")

    name_cell = html.at_css("#row_#{row.id} > td:first-child")
    expect(name_cell).to be_present
    expect(name_cell["class"]).to include("is-column-bold")
    expect(name_cell["class"]).to include("is-column-italic")
    expect(name_cell["class"]).to include("is-column-color-purple")
    expect(name_cell["class"]).to include("is-column-bg-rose")
  end

  it "marks row context style actions to preserve database scroll" do
    owner = User.create!(email: "database-row-menu-scroll-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Row Menu Scroll", slug: "tables-row-menu-scroll")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    row = DbRow.create!(workspace: workspace, database: database, title: "Q1")
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
    row_menu = html.at_css("#row_#{row.id} .notae-db-row-more-menu")
    expect(row_menu).to be_present
    expect(row_menu["data-row-menu-url-value"]).to include("panels/row_menu")
    expect(row_menu["data-row-menu-url-value"]).to include("row_id=#{row.id}")
    expect(row_menu.css("form")).to be_empty
    expect(response.body).not_to include("Duplicate row")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "row_menu", row_id: row.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    panel_html = Nokogiri::HTML.fragment(response.body)

    bold_form = panel_html.css("form").find do |form|
      form.at_css("input[name='db_row[style_action]'][value='toggle_bold']").present?
    end
    italic_form = panel_html.css("form").find do |form|
      form.at_css("input[name='db_row[style_action]'][value='toggle_italic']").present?
    end
    background_form = panel_html.css("form").find do |form|
      form.at_css("input[name='db_row[style_action]'][value='set_background_color']").present?
    end

    expect(response.body).to include("Duplicate row")
    expect(response.body).to include("Delete row")
    expect(bold_form).to be_present
    expect(italic_form).to be_present
    expect(background_form).to be_present
    expect(bold_form["data-preserve-database-scroll"]).to eq("true")
    expect(italic_form["data-preserve-database-scroll"]).to eq("true")
    expect(background_form["data-preserve-database-scroll"]).to eq("true")
  end

  it "renders progress properties with step controls and updates them inline" do
    owner = User.create!(email: "database-progress-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables Progress", slug: "tables-progress")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    progress_property = DbProperty.create!(workspace: workspace, database: database, name: "Progress", property_type: :progress)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship launch")
    cell = DbCell.create!(workspace: workspace, db_row: row, db_property: progress_property, value_text: "3")
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
    expect(response.body).to include("Progress")
    progress_field = html.at_css("#row_#{row.id} .notae-db-progress-field")
    expect(progress_field).to be_present
    expect(progress_field["data-controller"]).to include("progress-cell")
    expect(progress_field.at_css(".notae-db-progress-label")&.text).to eq("3/10")
    buttons = progress_field.css(".notae-db-progress-stepper")
    expect(buttons.map { |node| node.text.strip }).to eq([ "-", "+" ])

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: cell.id, view_id: view.id, progress_inline_update: "1"),
          params: { db_cell: { value_text: "10" } },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(turbo-stream action="replace" target="row_#{row.id}"))
    expect(response.body).to include("10/10")
    expect(cell.reload.value_text).to eq("10")
    expect(row.reload.data_json["Progress"]).to eq("10")
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

  it "sorts rows by the name field" do
    owner = User.create!(email: "database-name-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables name sort", slug: "tables-name-sort")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Leads")
    zulu_row = DbRow.create!(workspace: workspace, database: database, title: "Zulu Row")
    acme_row = DbRow.create!(workspace: workspace, database: database, title: "Acme Row")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: DatabaseView::NAME_SORT_KEY, sort_direction: "asc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index(acme_row.title)).to be < response.body.index(zulu_row.title)

    get database_path(workspace_slug: workspace.slug, id: database.id, sort_property_id: DatabaseView::NAME_SORT_KEY, sort_direction: "desc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index(zulu_row.title)).to be < response.body.index(acme_row.title)
  end

  it "sorts name values in calendar order for weekdays" do
    owner = User.create!(email: "database-calendar-name-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables calendar name sort", slug: "tables-calendar-name-sort")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Weekly cadence")
    sunday_row = DbRow.create!(workspace: workspace, database: database, title: "Sunday")
    wednesday_row = DbRow.create!(workspace: workspace, database: database, title: "Wednesday")
    monday_row = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    sign_in owner

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      sort_property_id: DatabaseView::NAME_SORT_KEY,
      sort_direction: "asc",
      sort_mode: "calendar"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body.index(monday_row.title)).to be < response.body.index(wednesday_row.title)
    expect(response.body.index(wednesday_row.title)).to be < response.body.index(sunday_row.title)

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      sort_property_id: DatabaseView::NAME_SORT_KEY,
      sort_direction: "desc",
      sort_mode: "calendar"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body.index(sunday_row.title)).to be < response.body.index(wednesday_row.title)
    expect(response.body.index(wednesday_row.title)).to be < response.body.index(monday_row.title)
  end

  it "sorts text property values in calendar order for months" do
    owner = User.create!(email: "database-calendar-property-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Tables calendar property sort", slug: "tables-calendar-property-sort")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Monthly roadmap")
    month_property = DbProperty.create!(workspace: workspace, database: database, name: "Month", property_type: :text)
    jan_row = DbRow.create!(workspace: workspace, database: database, title: "January task")
    apr_row = DbRow.create!(workspace: workspace, database: database, title: "April task")
    feb_row = DbRow.create!(workspace: workspace, database: database, title: "February task")
    DbCell.create!(workspace: workspace, db_row: jan_row, db_property: month_property, value_text: "Jan")
    DbCell.create!(workspace: workspace, db_row: apr_row, db_property: month_property, value_text: "Apr")
    DbCell.create!(workspace: workspace, db_row: feb_row, db_property: month_property, value_text: "Feb")
    sign_in owner

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      sort_property_id: month_property.id,
      sort_direction: "asc",
      sort_mode: "calendar"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body.index(jan_row.title)).to be < response.body.index(feb_row.title)
    expect(response.body.index(feb_row.title)).to be < response.body.index(apr_row.title)

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      sort_property_id: month_property.id,
      sort_direction: "desc",
      sort_mode: "calendar"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body.index(apr_row.title)).to be < response.body.index(feb_row.title)
    expect(response.body.index(feb_row.title)).to be < response.body.index(jan_row.title)
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
    database_shell = html.at_css("section.notae-db-split-layout[data-controller~='database-view-state']")
    expect(database_shell).to be_present
    expect(database_shell["data-action"]).to include("turbo:submit-start->database-view-state#capture")
    expect(database_shell["data-action"]).to include("click->database-view-state#captureLink")
    expect(database_shell["data-database-view-state-storage-key-value"]).to eq("database-view-scroll:#{database.id}")
    expect(html.at_css("tr#row_#{alpha_row.id}")["data-scroll-preserve-key"]).to eq("row_#{alpha_row.id}")
    expect(html.at_css("tr#row_#{bravo_row.id}")["data-scroll-preserve-key"]).to eq("row_#{bravo_row.id}")
    sort_form = html.css("form.notae-db-grid-property-sort-form[action='#{database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id)}']").find do |form|
      form.at_css("input[name='database_view[sort_property_id]'][value='#{db_property.id}']")
    end
    expect(sort_form).to be_present
    expect(sort_form["data-preserve-database-scroll"]).to eq("true")
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

  it "persists name header sorts in the current view config" do
    owner = User.create!(email: "database-persistent-name-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Persistent name sort tables", slug: "persistent-name-sort-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Pipeline")
    zulu_row = DbRow.create!(workspace: workspace, database: database, title: "Zulu Row")
    acme_row = DbRow.create!(workspace: workspace, database: database, title: "Acme Row")
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
    name_sort_form = html.css("form.notae-db-grid-property-sort-form[action='#{database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id)}']").find do |form|
      form.at_css("input[name='database_view[sort_property_id]'][value='#{DatabaseView::NAME_SORT_KEY}']")
    end
    expect(name_sort_form).to be_present
    expect(name_sort_form.at_css("input[name='database_view[sort_direction]'][value='asc']")).to be_present

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              sort_property_id: DatabaseView::NAME_SORT_KEY,
              sort_direction: "asc"
            }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id))
    expect(view.reload.config_json).to include(
      "sort_property_id" => DatabaseView::NAME_SORT_KEY,
      "sort_direction" => "asc"
    )

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: view.id)

    expect(response).to have_http_status(:ok)
    expect(response.body.index(acme_row.title)).to be < response.body.index(zulu_row.title)
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
      filter_operator: "neq",
      filter_value: "2"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Low estimate")
    expect(response.body).to include("High estimate")

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

  it "renders the expanded filter operator list with clearer date and number wording" do
    owner = User.create!(email: "database-filter-operators-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Filter operators tables", slug: "filter-operators-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Filter operators DB")
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "view_settings", view_id: view.id, view_settings: "open")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Does not equal")
    expect(response.body).to include("Before / less than")
    expect(response.body).to include("After / greater than")
    expect(response.body).to include("For dates, before/after means earlier or later. For numbers, it means less than or greater than.")
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
    unassigned_column = document.css(".notae-db-board-column").find do |node|
      node.at_css(".notae-db-board-column-title")&.text.to_s.include?("Unassigned")
    end
    started_column = document.at_css(".notae-db-board-column-title.is-status-started")
    done_column = document.at_css(".notae-db-board-column-title.is-status-done")

    expect(response.body).not_to include("notae-db-toolbar-new")
    expect(document.css(".notae-db-board-column-add").length).to eq(1)
    expect(unassigned_column).to be_present
    expect(unassigned_column.at_css(".notae-db-board-column-add")["title"]).to eq("add new unassigned card")
    expect(started_column&.text.to_s).to include("Started")
    expect(done_column&.text.to_s).to include("Done")
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
    document = Nokogiri::HTML.parse(response.body)
    notes_value = document.css(".notae-db-board-card-detail-row").find do |node|
      node.at_css(".notae-db-board-card-detail-label")&.text&.strip == "Notes"
    end&.at_css(".notae-db-board-card-detail-value")
    expect(notes_value).to be_present
    expect(notes_value["title"]).to eq("Follow up with vendor")
  end

  it "renders a board card dialog with all editable row fields and row options" do
    owner = User.create!(email: "database-board-dialog-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Board dialog tables", slug: "board-dialog-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Board dialog")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    estimate_property = DbProperty.create!(workspace: workspace, database: database, name: "Estimate", property_type: :number)
    blocked_property = DbProperty.create!(workspace: workspace, database: database, name: "Blocked", property_type: :checkbox)
    notes_property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Dialog row")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-03")
    DbCell.create!(workspace: workspace, db_row: row, db_property: estimate_property, value_text: "3")
    DbCell.create!(workspace: workspace, db_row: row, db_property: blocked_property, value_text: "true")
    DbCell.create!(workspace: workspace, db_row: row, db_property: notes_property, value_text: "Check the final scope")
    board_view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Board dialog",
      view_type: :board,
      config_json: { "group_property_id" => status_property.id },
      default: true
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, view_id: board_view.id)

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML.parse(response.body)
    card = document.at_css("#board_row_#{row.id}")
    dialog = card.at_css(".notae-db-board-card-modal")
    labels = dialog.css(".notae-db-board-card-modal-label").map(&:text).map(&:strip)

    expect(card["data-action"]).to include("dblclick->database-drag#beginEdit")
    expect(dialog).to be_present
    expect(dialog.at_css("input#board_row_title_#{row.id}[name='db_row[title]']")).to be_present
    expect(dialog.at_css("form.notae-db-board-card-modal-title-form")["data-action"]).to include("turbo:submit-end->database-drag#refreshBoardOnSubmit")
    expect(labels).to include("Title", "Status", "Due date", "Estimate", "Blocked", "Notes")
    row_menu = dialog.at_css("[data-controller='row-menu']")
    expect(row_menu).to be_present
    expect(row_menu["data-row-menu-url-value"]).to include("panels/row_menu")
    expect(row_menu["data-row-menu-url-value"]).to include("row_id=#{row.id}")
    expect(row_menu.css("form")).to be_empty
    status_select = dialog.at_css("select[name='db_cell[value_text]']")
    due_date_input = dialog.at_css("input[type='date'][name='db_cell[value_text]']")
    estimate_input = dialog.at_css("input[type='number'][name='db_cell[value_text]']")
    blocked_input = dialog.at_css("input[type='checkbox'][name='db_cell[value_text]']")
    notes_input = dialog.at_css("input[type='text'][name='db_cell[value_text]']")

    expect(status_select).to be_present
    expect(due_date_input).to be_present
    expect(estimate_input).to be_present
    expect(blocked_input).to be_present
    expect(notes_input).to be_present
    expect(status_select.ancestors("form").first["data-action"]).to include("turbo:submit-end->database-drag#refreshBoardOnSubmit")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "row_menu", row_id: row.id, view_id: board_view.id)
    expect(response).to have_http_status(:ok)
    row_menu_body = Nokogiri::HTML.fragment(response.body)
    expect(row_menu_body.at_css("form[action='#{duplicate_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)}']")).to be_present
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

  it "renders redirect notices in the local grid flash host instead of the shell top" do
    owner = User.create!(email: "database-inline-flash-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Inline grid flash", slug: "inline-grid-flash")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Untitled grid")
    Databases::EnsureLinkedPageService.call(database: database, actor: owner)
    sign_in owner

    patch page_path(workspace_slug: workspace.slug, id: database.linked_page.id),
          params: {
            return_to: database_path(workspace_slug: workspace.slug, id: database.id),
            page: { root_tab_title: "Overview" }
          }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    follow_redirect!

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("#database_flash_messages .notae-flash.notice")&.text&.strip).to eq("Page updated.")
    expect(html.at_css("#notae_flash_messages .notae-flash")).to be_nil
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
             sort_mode: "calendar",
             filter_property_id: status_property.id,
             filter_operator: "neq",
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
      "sort_mode" => "calendar",
      "filter_property_id" => status_property.id,
      "filter_operator" => "neq",
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
    page_body = response.body

    expect(response).to have_http_status(:ok)
    expect(page_body).to include("Aa")
    expect(page_body).to include("Name")
    expect(page_body).to include("+ Add property")
    expect(page_body).to include("notae-db-new-row-trigger-form")
    expect(page_body).to include("notae-db-grid-add-row-control")
    expect(page_body).to include("+ New row")
    expect(page_body).not_to include("notae-db-toolbar-new")
    expect(page_body).not_to include("notae-db-grid-new-row")
    expect(page_body).not_to include("Link &amp; add row")
    expect(page_body).to include("Add icon")
    expect(page_body).to include("Add cover")
    expect(page_body).to include("Add description")
    expect(page_body).to include('aria-label="Add icon"')
    expect(page_body).to include('aria-label="Add cover"')
    expect(page_body).to include('aria-label="Add description"')
    expect(page_body).to include('class="notae-page-header-action-label"')
    expect(page_body).to include("View settings")
    expect(page_body).to include("Options")
    expect(page_body).to include("notae-db-actions-menu")
    expect(page_body).to include("panels/actions")
    expect(page_body).to include("panels/options")
    expect(page_body).to include("panels/view_settings")
    expect(page_body).not_to include("Open linked page")
    expect(page_body).to include("notae-page-header-cover-panel")
    expect(page_body).to include("cover-picker")
    expect(page_body).not_to include("notae-cover-picker-grid")
    expect(page_body).not_to include("data-controller=\"cover-carousel\"")
    expect(page_body).to include("Move up")
    expect(page_body).to include("Move down")
    expect(page_body).to include("notae-db-settings-menu")
    expect(page_body).not_to include("notae-page-emoji-grid")
    expect(page_body).to include("name=\"database[name]\"")
    expect(page_body).to include("notae-page-title-input")
    expect(page_body).not_to include("Property visibility")
    expect(page_body).not_to include("Conditional color")
    expect(page_body).not_to include("Public share links")
    expect(page_body).not_to include("Archived rows")
    expect(page_body).not_to include("Version history")
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DatabasesController#show")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    expect(response.body).not_to include("db-edit-view-panel")
    expect(response.body).not_to include("notae-db-view-plus")

    get workspace_icon_picker_path(workspace_slug: workspace.slug, target_type: "database", database_id: database.id, fallback: "🗃️")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("🧠")

    html = Nokogiri::HTML(page_body)
    title_field = html.at_css("textarea.notae-page-title-input[name='database[name]']")
    expect(title_field).to be_present
    expect(title_field["rows"]).to eq("1")
    expect(title_field["wrap"]).not_to eq("off")
    expect(html.at_css("#database-actions-menu[data-lazy-panel-url-value*='panels/actions']")).to be_present
    expect(html.at_css("#database-options-menu[data-lazy-panel-url-value*='panels/options']")).to be_present
    expect(page_body).to include('data-action="toggle->shell#syncTopbarMenus lazy-panel:loaded->actions-menu#refresh"')
    expect(page_body).to include('data-action="toggle->shell#syncTopbarMenus lazy-panel:loaded->options-menu#refresh"')
    expect(page_body).to include('data-action="toggle->shell#syncTopbarMenus"')
    expect(html.at_css(".notae-db-settings-menu[data-lazy-panel-url-value*='panels/view_settings']")).to be_present
    table_rows = html.css(".notae-db-grid tbody tr")
    expect(table_rows).not_to be_empty
    expect(table_rows.last["class"]).to include("notae-db-grid-add-row-control")
    expect(table_rows.map { |row| row["class"] }.join(" ")).not_to include("notae-db-grid-new-row")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "actions")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-actions-font-grid")
    expect(response.body).to include("Copy link to view")
    expect(response.body).to include("Move to Trash")
    expect(response.body).to include("Version history")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "options")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Permissions")
    expect(response.body).to include("Public share links")
    expect(response.body).to include("Archived rows")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "view_settings")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Layout")
    expect(response.body).to include("Timeline")
    expect(response.body).to include("Kanban board")
    expect(response.body).to include("Map")
    expect(response.body).to include("Property visibility")
    expect(response.body).to include("Conditional color")
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

  it "enqueues a backfill job for missing cells and renders them after the async repair runs" do
    owner = User.create!(email: "database-backfill-cell-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Backfill cells tables", slug: "backfill-cells-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Backfill DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Row one")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    cell = DbCell.create!(workspace: workspace, db_row: row, db_property: property, value_text: "")
    cell.destroy!
    sign_in owner

    expect do
      get database_path(workspace_slug: workspace.slug, id: database.id)
    end.to have_enqueued_job(DbCells::BackfillWindowJob).with(database.id, [ row.id ], [ property.id ])

    expect(response).to have_http_status(:ok)
    expect(DbCell.find_by(workspace: workspace, db_row: row, db_property: property)).to be_nil

    perform_enqueued_jobs

    recreated_cell = DbCell.find_by!(workspace: workspace, db_row: row, db_property: property)

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
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

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response.body).to include("Locked grid")
    expect(response.body).to include("This grid is view-only right now.")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "view_settings", view_settings: "open")
    expect(response).to have_http_status(:ok)
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
    expect(response.body).to include("data-controller=\"lazy-panel\"")
    expect(response.body).not_to include("data-controller=\"cover-carousel\"")
    expect(response.body).not_to include("notae-cover-picker-grid")
    expect(response.body).not_to include("notae-cover-picker-upload-form")

    get workspace_cover_picker_path(
      workspace_slug: workspace.slug,
      target_type: "database",
      database_id: database.id,
      embedded: true,
      allow_remove: true,
      remove_label: "Remove cover"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-controller=\"cover-carousel\"")
    expect(response.body).to include("Browse Unsplash")
    expect(response.body).to include("Original")
    expect(response.body).to include("Vector")
    expect(response.body).to include("Pastel")
    expect(response.body).to include("Bold")
    expect(response.body).to include("Gradient")
    expect(response.body).to include('data-cover-carousel-target="uploadInput"')
    expect(response.body).to include('data-cover-carousel-target="uploadError"')

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

  it "applies Unsplash covers to a grid header and reuses them from recent covers" do
    owner = User.create!(email: "database-header-unsplash-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database Unsplash", slug: "database-unsplash")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Unsplash DB")
    sign_in owner

    client = instance_double(
      Unsplash::Client,
      photo: {
        id: "grid-photo-2",
        alt: "City glow",
        preview_url: "https://images.unsplash.com/grid-photo-2-small",
        full_url: "https://images.unsplash.com/grid-photo-2-regular",
        artist_name: "Noah Lens",
        artist_url: "https://unsplash.com/@noah?utm_source=notae&utm_medium=referral",
        source_name: "Unsplash",
        source_url: "https://unsplash.com/?utm_source=notae&utm_medium=referral",
        download_location: "https://api.unsplash.com/photos/grid-photo-2/download"
      }
    )
    allow(client).to receive(:register_download!).with("https://api.unsplash.com/photos/grid-photo-2/download")
    allow(Unsplash::Client).to receive(:new).and_return(client)

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { cover_action: "unsplash", cover_remote_id: "grid-photo-2" } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.cover_remote_url).to eq("https://images.unsplash.com/grid-photo-2-regular")
    expect(database.cover_artist_name).to eq("Noah Lens")

    recent_asset = workspace.cover_assets.find_by!(created_by: owner, source_kind: "unsplash", external_id: "grid-photo-2")

    patch database_path(workspace_slug: workspace.slug, id: database.id),
          params: { database: { cover_action: "recent", cover_asset_id: recent_asset.id } }

    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id))
    expect(database.reload.cover_remote_url).to eq("https://images.unsplash.com/grid-photo-2-regular")

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response.body).to include("Photo by")

    get workspace_cover_picker_path(
      workspace_slug: workspace.slug,
      target_type: "database",
      database_id: database.id,
      embedded: true,
      allow_remove: true,
      remove_label: "Remove cover"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Recent")
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
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include("Row updated.")
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DbRowsController#update")
    expect(row.reload.title).to eq("Renamed row")
    expect(database.reload.updated_at).to be > previous_database_updated_at
  end

  it "updates row colors with turbo streams instead of redirecting the whole grid" do
    owner = User.create!(email: "database-row-color-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row color turbo tables", slug: "row-color-turbo-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row color turbo DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Color me")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { style_action: "set_color", text_color: "green" } },
          as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include('turbo-stream action="update" target="database_topbar_edited_at"')
    expect(response.body).to include(%(turbo-stream action="replace" target="row_#{row.id}"))
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include("Row updated.")
    expect(row.reload.row_text_color).to eq("green")
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
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include("Row updated.")
    expect(response.body).to include('data-auto-submit-focus-on-connect-value="true"')
    expect(response.body).to include("is-new-row-highlight")
    expect(first_row.reload.title).to eq("Updated first row")
    expect(DbRow.for_database(database).active.ordered.pluck(:id)).to eq([ first_row.id, created_row.id, second_row.id ])
  end

  it "paginates table rows while keeping the total row count visible" do
    owner = User.create!(email: "database-pagination-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Pagination tables", slug: "pagination-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Paginated grid")
    65.times do |index|
      DbRow.create!(workspace: workspace, database: database, title: format("Row %02d", index + 1))
    end
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    rendered_row_ids = document.css("#database_table_rows tr[id^='row_']").map { |row| row["id"] }
    expect(rendered_row_ids.length).to eq(25)
    expect(response.body).to include("Page 1 of 3")
    expect(document.at_css("#database_row_count")&.text).to include("65 rows")
    expect(response.body).to include("Row 01")
    expect(response.body).not_to include("Row 65")

    get database_path(workspace_slug: workspace.slug, id: database.id, rows_page: 2)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    rendered_row_ids = document.css("#database_table_rows tr[id^='row_']").map { |row| row["id"] }
    expect(rendered_row_ids.length).to eq(25)
    expect(response.body).to include("Page 2 of 3")
    expect(response.body).to include("Row 26")
    expect(response.body).not_to include("Row 65")

    get database_path(workspace_slug: workspace.slug, id: database.id, rows_page: 3)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    rendered_row_ids = document.css("#database_table_rows tr[id^='row_']").map { |row| row["id"] }
    expect(rendered_row_ids.length).to eq(15)
    expect(response.body).to include("Page 3 of 3")
    expect(response.body).to include("Row 65")
  end

  it "keeps inline grid edit forms lightweight for initial table rendering" do
    owner = User.create!(email: "database-lightweight-grid-forms-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Lightweight grid forms", slug: "lightweight-grid-forms")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Lean grid")
    property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Lean row")
    cell = DbCell.create!(workspace: workspace, db_row: row, db_property: property, value_text: "Keep payload small")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    table_body = document.at_css("#database_table_rows")
    title_form = document.at_css("#row_#{row.id} form.notae-db-title-form-inline")
    cell_form = document.css("form").find { |form| form["action"].to_s.include?(cell.id) }
    cell_input = document.at_css("#db_cell_#{cell.id}_value_text")
    insert_row_form = document.at_css("#row_#{row.id} form.notae-db-row-hover-control-form")

    expect(table_body).to be_present
    expect(table_body["data-controller"].split).to include("db-table-reorder", "auto-submit")
    expect(title_form).to be_present
    expect(cell_form).to be_nil
    expect(cell_input).to be_present
    expect(cell_input["data-action"]).to include("change->auto-submit#submit")
    expect(cell_input["data-auto-submit-url"]).to eq(
      database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: cell.id, view_id: database.database_views.first.id)
    )
    expect(cell_input["data-auto-submit-method"]).to eq("patch")
    expect(cell_input["data-auto-submit-param-name"]).to eq("db_cell[value_text]")
    expect(insert_row_form).to be_present
    expect(title_form.at_css("input[name='authenticity_token']")).to be_nil
    expect(insert_row_form.at_css("input[name='authenticity_token']")).to be_nil
    expect(title_form.at_css("input[name='_method'][value='patch']")).to be_present
    expect(insert_row_form.at_css("input[name='db_row[title]'][value='Untitled row']")).to be_present
    expect(title_form["data-controller"]).to be_nil
    expect(document.css("[data-controller~='auto-submit']").size).to eq(1)
  end

  it "creates a new row with turbo streams instead of redirecting the full grid for the simple table path" do
    owner = User.create!(email: "database-row-create-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create turbo tables", slug: "row-create-turbo-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create turbo DB")
    sign_in owner

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { db_row: { title: "Untitled row" } },
         as: :turbo_stream

    created_row = database.db_rows.order(:created_at).last
    expect(created_row).to be_present
    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("DbRowsController#create")
    expect(response.body).to include('turbo-stream action="append" target="database_table_rows"')
    expect(response.body).to include('turbo-stream action="update" target="database_row_count"')
    expect(response.body).to include('turbo-stream action="update" target="database_table_placeholders"')
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include('data-auto-submit-focus-on-connect-value="true"')
    expect(response.body).to include('data-preserve-database-scroll="true"')
    expect(response.body).to include("is-new-row-highlight")
    expect(response.body).not_to include('autofocus="autofocus"')
  end

  it "archives a row with turbo streams so the table stays in place" do
    owner = User.create!(email: "database-row-destroy-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row destroy turbo tables", slug: "row-destroy-turbo-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row destroy turbo DB")
    row = DbRow.create!(workspace: workspace, database: database, title: "Archive me")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    row_menu = html.at_css("#row_#{row.id} .notae-db-row-more-menu")
    expect(row_menu).to be_present
    expect(row_menu["data-row-menu-url-value"]).to include("panels/row_menu")
    expect(html.css("#row_#{row.id} .notae-db-row-more-menu form")).to be_empty

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "row_menu", row_id: row.id)
    expect(response).to have_http_status(:ok)
    row_menu_body = Nokogiri::HTML.fragment(response.body)
    delete_form = row_menu_body.css("form[action='#{database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)}']").find do |form|
      form.at_css("input[name='_method'][value='delete']").present?
    end
    expect(delete_form).to be_present
    expect(delete_form["data-preserve-database-scroll"]).to eq("true")

    delete database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
           as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(row.reload.archived_at).to be_present
    expect(response.body).to include('turbo-stream action="remove" target="row_')
    expect(response.body).to include("row_#{row.id}")
    expect(response.body).to include('turbo-stream action="update" target="database_row_count"')
    expect(response.body).to include('turbo-stream action="update" target="database_table_placeholders"')
    expect(response.body).to include('turbo-stream action="replace" target="database_flash_messages"')
    expect(response.body).to include("Row archived.")
  end

  it "enqueues a single row reindex job when creating a fresh row" do
    clear_enqueued_jobs

    owner = User.create!(email: "database-row-create-job-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row create jobs", slug: "row-create-jobs")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row create jobs DB")
    DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select, position: 1024)
    DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text, position: 2048)
    sign_in owner

    expect do
      post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
           params: { db_row: { title: "Untitled row" } },
           as: :turbo_stream
    end.to have_enqueued_job(Search::IndexDbRowJob).exactly(:once)
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
      database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{created_row.id}", highlight_row_id: created_row.id)
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
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: database.id, anchor: "row_#{inserted_row.id}"))
    ordered_ids = DbRow.for_database(database).active.ordered.pluck(:id)
    expect(ordered_ids).to eq([ first_row.id, inserted_row.id, second_row.id ])
  end

  it "inserts a newly created row below the referenced row with turbo streams for the simple table path" do
    owner = User.create!(email: "database-row-insert-turbo-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row insert turbo tables", slug: "row-insert-turbo-tables")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Row insert turbo DB")
    first_row = DbRow.create!(workspace: workspace, database: database, title: "First")
    second_row = DbRow.create!(workspace: workspace, database: database, title: "Second")
    sign_in owner

    post database_db_rows_path(workspace_slug: workspace.slug, database_id: database.id),
         params: { insert_after_id: first_row.id, db_row: { title: "Inserted" } },
         as: :turbo_stream

    inserted_row = database.db_rows.find_by!(title: "Inserted")
    expect(inserted_row).to be_present
    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect
    expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
    expect(response.body).to include(%(turbo-stream action="after" target="row_#{first_row.id}"))
    expect(response.body).to include(%(id="row_#{inserted_row.id}"))
    expect(DbRow.for_database(database).active.ordered.pluck(:id)).to eq([ first_row.id, inserted_row.id, second_row.id ])
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
        DbRow::ROW_STYLE_COLOR_KEY => "purple",
        DbRow::ROW_STYLE_BACKGROUND_COLOR_KEY => "mint"
      }
    )
    tail_row = DbRow.create!(workspace: workspace, database: database, title: "Tail row")
    DbCell.create!(workspace: workspace, db_row: source_row, db_property: status_property, value_text: "In progress")
    sign_in owner

    clear_enqueued_jobs

    expect do
      post duplicate_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: source_row.id)
    end.to have_enqueued_job(Search::IndexDbRowJob).exactly(:once)

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
    expect(duplicate_row.row_background_color).to eq("mint")
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
    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: { db_row: { style_action: "set_background_color", background_color: "lemon" } }

    row.reload
    expect(row.row_bold?).to eq(true)
    expect(row.row_italic?).to eq(true)
    expect(row.row_text_color).to eq("blue")
    expect(row.row_background_color).to eq("lemon")

    patch database_db_cell_path(workspace_slug: workspace.slug, database_id: database.id, id: cell.id),
          params: { db_cell: { value_text: "Done" } }

    row.reload
    expect(row.row_bold?).to eq(true)
    expect(row.row_italic?).to eq(true)
    expect(row.row_text_color).to eq("blue")
    expect(row.row_background_color).to eq("lemon")
    expect(row.data_json["Status"]).to eq("Done")

    get database_path(workspace_slug: workspace.slug, id: database.id)
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    styled_row = html.at_css("#row_#{row.id}")
    expect(styled_row).to be_present
    expect(styled_row["class"]).to include("is-row-bold")
    expect(styled_row["class"]).to include("is-row-italic")
    expect(styled_row["class"]).to include("is-row-bg-lemon")
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
      config_json: { "sort_property_id" => status_property.id, "sort_direction" => "asc", "sort_mode" => "calendar" }
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
    expect(payload["redirect_url"]).not_to include("sort_mode")
    expect(view.reload.config_json).not_to have_key("sort_property_id")
    expect(view.reload.config_json).not_to have_key("sort_direction")
    expect(view.reload.config_json).not_to have_key("sort_mode")
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
    split_actions = html.at_css(".notae-db-split-pane-actions")
    expect(split_actions).to be_present
    open_full_link = split_actions.at_css("a.notae-chip-button")
    expect(open_full_link).to be_present
    expect(open_full_link["href"]).to eq(page_path(workspace_slug: workspace.slug, id: row.linked_page_id))
    expect(open_full_link["target"]).to be_nil
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
    expect(html.at_css("#database_table_rows")["data-controller"].split).to include("auto-submit")
    expect(title_form["data-controller"]).to be_nil
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

    link_chooser = row_node.at_css(".notae-db-row-link-chooser")
    expect(link_chooser).to be_present
    expect(link_chooser["data-controller"].split).to include("lazy-panel")
    expect(link_chooser["data-lazy-panel-url-value"]).to include(
      panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "row_link_chooser")
    )
    expect(link_chooser["data-lazy-panel-url-value"]).to include("row_id=#{row.id}")
    expect(link_chooser.at_css("[data-lazy-panel-target='container']")).to be_present
    expect(row_node.at_css("form[data-controller='document-picker']")).to be_nil
    expect(row_node.to_html).not_to include("db_row_link_page_search_#{row.id}")

    get link_chooser["data-lazy-panel-url-value"]

    expect(response).to have_http_status(:ok)
    panel_html = Nokogiri::HTML.fragment(response.body)
    picker_form = panel_html.at_css("form.notae-db-inline-form[data-controller='document-picker']")
    expect(picker_form).to be_present
    expect(picker_form["action"]).to include(database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id))
    expect(picker_form["data-document-picker-search-url-value"]).to eq(
      workspace_document_targets_path(workspace_slug: workspace.slug, kind: "page")
    )
    expect(picker_form.at_css("input[name='db_row_link_page_search_#{row.id}']")).to be_present
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
        split_row_id: created_row.id,
        anchor: "row_#{created_row.id}"
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
        split_row_id: chosen_row.id,
        anchor: "row_#{chosen_row.id}"
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
    expect(response.body).to include(database_path(workspace_slug: workspace.slug, id: database.id, embedded: "1"))
    expect(response.body).not_to include("http://localhost:4000")
  end

  it "opens a Kalendārium split pane scoped to the Tasks project" do
    owner = User.create!(email: "database-kal-split-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal split", slug: "grid-kal-split")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "kalendarium")

    expect(response).to have_http_status(:ok)

    tasks_project = workspace.kalendarium_projects.find_by!(slug: "tasks")
    expect(tasks_project.kalendarium_calendar).to be_present
    expect(response.body).not_to include("Find space in my calendar")

    html = Nokogiri::HTML(response.body)
    row = database.db_rows.find_by!(title: "Review roadmap")
    row_menu = html.at_css("#row_#{row.id} .notae-db-row-more-menu")
    expect(row_menu).to be_present
    expect(row_menu["data-row-menu-url-value"]).to include("panels/row_menu")

    get panel_database_path(workspace_slug: workspace.slug, id: database.id, panel: "row_menu", row_id: row.id, split_panel: "kalendarium")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Find space in my calendar")

    split_iframe = html.at_css("iframe[title='Kalendārium side peek']")
    expect(split_iframe).to be_present
    expect(split_iframe["src"]).to include("/w/#{workspace.slug}/kalendarium")
    expect(split_iframe["src"]).to include("view=next_7_days")
    expect(split_iframe["src"]).to include("window_start=#{Date.current}")
    expect(split_iframe["src"]).to include("embedded=1")
    expect(split_iframe["src"]).to include("project_id=#{tasks_project.id}")
    expect(split_iframe["src"]).to include("project_scope_id=#{tasks_project.id}")

    kalendarium_button = html.css(".notae-db-template-actions a").find { |link| link.text.strip == "Kalendārium" }
    expect(kalendarium_button).to be_present
    expect(kalendarium_button["class"]).to include("is-active")
  end

  it "opens a Gantt split pane for rows with start and end dates" do
    owner = User.create!(email: "database-gantt-split-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt split", slug: "grid-gantt-split")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-18")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "gantt")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    split_title = html.at_css(".notae-db-split-pane-title")
    expect(split_title.text).to include("Gantt")
    expect(html.at_css(".notae-db-gantt-bar-wrap")).to be_present
    expect(html.at_css("[data-board-card-dialog]")).to be_present
    expect(html.css(".notae-db-split-view-option").map { |node| node.text.strip }).to include("Default", "Kanban board", "Kalendārium", "Gantt")
    color_input = html.at_css('.notae-db-gantt-status-swatch input[type="color"]')
    expect(color_input).to be_present
    expect(color_input["data-action"]).to include("updateRowColor")
    toolbar_buttons = html.css(".notae-db-gantt-toolbar button.notae-chip-button.notae-db-template-button").map { |node| node.text.squish }
    expect(toolbar_buttons).to eq([ "Print to PDF", "Copy to Nota" ])
    expect(html.at_css(".notae-db-gantt-toolbar [data-button-feedback-label]")&.text).to eq("Print to PDF")
    expect(html.at_css(".notae-db-gantt-toolbar [data-copy-text-feedback]")&.text).to eq("Copy to Nota")
    expect(html.css(".notae-db-gantt-toolbar button[data-controller='button-feedback']").map { |node| node.text.squish }).to eq([ "Print to PDF", "Copy to Nota" ])
    expect(response.body).to include("data-copy-text-html-value=")
    expect(response.body).to include("data-notae-gantt-embed=&quot;1&quot;")
    expect(response.body).to include("/gantt_embed")
    expect(response.body).not_to include("Gantt chart ·")
    expect(response.body).not_to include("Change colour for")
    expect(response.body).not_to include("Drag the bar edge to extend the finish date.")

    views_button = html.css(".notae-db-split-view-menu > summary").find { |node| node.text.squish.start_with?("Views") }
    expect(views_button["class"]).to include("is-active")
    expect(views_button.at_css(".notae-db-split-view-caret")&.text).to eq("▾")
  end

  it "opens a graph split pane with visible numeric series and graph actions" do
    owner = User.create!(email: "database-graph-split-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph split", slug: "grid-graph-split")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number)
    DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    q1 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    q2 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 2")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: margin_property, value_text: "45")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: revenue_property, value_text: "160")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: margin_property, value_text: "52")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "line" }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    split_title = html.at_css(".notae-db-split-pane-title")
    expect(split_title.text).to include("Graph")
    expect(html.at_css(".notae-db-graph-svg")).to be_present
    expect(html.css(".notae-db-graph-series-line").length).to eq(2)
    expect(html.css(".notae-db-graph-legend-item").map { |node| node.text.squish }).to include("Revenue", "Margin")
    expect(html.css(".notae-db-graph-value-label")).to be_empty
    expect(response.body).to include("Line graph")
    expect(response.body).to include("Bar graph")
    expect(response.body).to include("Pie graph")
    expect(response.body).to include("Stats")
    expect(response.body).to include("Show values")
    expect(response.body).to include("Split graph")
    expect(response.body).to include("data-notae-graph-embed=&quot;1&quot;")
    expect(response.body).to include("/graph_embed")
    toolbar_buttons = html.css(".notae-db-chart-toolbar .notae-chip-button.notae-db-gantt-toolbar-button").map { |node| node.text.squish }
    expect(toolbar_buttons).to eq([ "Print to PDF", "Copy to Nota" ])
    expect(html.at_css(".notae-db-chart-toolbar [data-button-feedback-label]")&.text).to eq("Print to PDF")
    expect(html.at_css(".notae-db-chart-toolbar [data-copy-text-feedback]")&.text).to eq("Copy to Nota")
    expect(html.css(".notae-db-chart-toolbar button[data-controller='button-feedback']").map { |node| node.text.squish }).to eq([ "Print to PDF", "Copy to Nota" ])
    expect(html.css(".notae-db-split-view-option").map { |node| node.text.strip }).to include("Graph")
  end

  it "renders split graphs below the main graph when split graph is enabled" do
    owner = User.create!(email: "database-graph-split-series-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph split series", slug: "grid-graph-split-series")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number)
    monday = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    tuesday = DbRow.create!(workspace: workspace, database: database, title: "Tuesday")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: revenue_property, value_text: "100")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: margin_property, value_text: "5")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: revenue_property, value_text: "140")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: margin_property, value_text: "7")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "line", "graph_split_series" => true }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.css(".notae-db-graph-svg").length).to eq(3)
    expect(html.css(".notae-db-graph-split-item").length).to eq(2)
    expect(html.css(".notae-db-graph-split-item .notae-db-graph-series-line").length).to eq(2)
    expect(html.css(".notae-db-graph-split-item .notae-db-graph-legend-label").map { |node| node.text.squish }).to eq([ "Revenue", "Margin" ])
    expect(html.css(".notae-db-graph-split-item .notae-db-graph-legend-swatch input[type='color']").length).to eq(2)
    expect(response.body).to include("Recombine")
  end

  it "renders stats graphs with black rising segments and red flat or falling segments" do
    owner = User.create!(email: "database-graph-stats-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph stats", slug: "grid-graph-stats")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    monday = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    tuesday = DbRow.create!(workspace: workspace, database: database, title: "Tuesday")
    wednesday = DbRow.create!(workspace: workspace, database: database, title: "Wednesday")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: revenue_property, value_text: "100")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: revenue_property, value_text: "140")
    DbCell.create!(workspace: workspace, db_row: wednesday, db_property: revenue_property, value_text: "140")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: {
        "graph_type" => "stats",
        "graph_series_colors" => {
          revenue_property.id.to_s => "#123456"
        }
      }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(response.body).to include("Stats")
    expect(html.css(".notae-db-graph-series-line").length).to eq(2)
    expect(response.body).to include("--notae-graph-series-color: #111111;")
    expect(response.body).to include("--notae-graph-series-color: #DC2626;")
    expect(html.css(".notae-db-graph-legend-swatch input[type='color']")).to be_empty
    expect(html.css(".notae-db-graph-legend-swatch.is-static").length).to eq(1)
  end

  it "does not keep the view settings menu open when graph toolbar actions are submitted" do
    owner = User.create!(email: "database-graph-toolbar-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph toolbar", slug: "grid-graph-toolbar")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    row = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    DbCell.create!(workspace: workspace, db_row: row, db_property: revenue_property, value_text: "100")
    view = DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "line" }
    )
    sign_in owner

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      split_panel: "graph",
      view_id: view.id,
      view_settings: "open",
      view_settings_section: "visibility"
    )

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    graph_forms = html.css(
      ".notae-db-graph-pane form.notae-db-split-view-form, " \
      ".notae-db-graph-pane form.notae-db-chart-toolbar-toggle-form, " \
      ".notae-db-graph-pane form.notae-db-graph-legend-form"
    )
    hidden_field_names = graph_forms.flat_map { |form| form.css("input[type='hidden']").map { |input| input["name"] } }

    expect(hidden_field_names).not_to include("view_settings")
    expect(hidden_field_names).not_to include("view_settings_section")
  end

  it "renders a graph unavailable message when no visible numeric values exist" do
    owner = User.create!(email: "database-graph-empty-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph empty", slug: "grid-graph-empty")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Notes")
    DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Graph unavailable")
    expect(response.body).to include("numeric values")
  end

  it "renders pie graph slices as percentages of the whole" do
    owner = User.create!(email: "database-graph-pie-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph pie", slug: "grid-graph-pie")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    profit_property = DbProperty.create!(workspace: workspace, database: database, name: "Profit", property_type: :number)
    q1 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    q2 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 2")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: revenue_property, value_text: "60")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: profit_property, value_text: "40")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: revenue_property, value_text: "30")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: profit_property, value_text: "20")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "pie", "graph_show_values" => true }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("66.7%")
    expect(response.body).to include("33.3%")
    expect(response.body).to include("<title>Quarter 1: 66.7%</title>")
    expect(response.body).to include("<title>Quarter 2: 33.3%</title>")
    expect(response.body).not_to include("<title>Revenue:")
  end

  it "renders a full pie circle when only one visible numeric series exists" do
    owner = User.create!(email: "database-graph-single-pie-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph single pie", slug: "grid-graph-single-pie")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    notes_property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    DbCell.create!(workspace: workspace, db_row: row, db_property: revenue_property, value_text: "60")
    DbCell.create!(workspace: workspace, db_row: row, db_property: notes_property, value_text: "steady")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "pie", "graph_show_values" => true }
    )
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<circle")
    expect(response.body).to include("class=\"notae-db-graph-pie-slice\"")
    expect(response.body).to include("<title>Quarter 1: 100%</title>")
    expect(response.body).to include(">100%</text>")
  end

  it "respects the source grid filtering and ordering in the graph split pane" do
    owner = User.create!(email: "database-graph-filter-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph filter", slug: "grid-graph-filter")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    alpha = DbRow.create!(workspace: workspace, database: database, title: "Alpha")
    beta = DbRow.create!(workspace: workspace, database: database, title: "Beta")
    gamma = DbRow.create!(workspace: workspace, database: database, title: "Gamma")
    DbCell.create!(workspace: workspace, db_row: alpha, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: alpha, db_property: status_property, value_text: "active")
    DbCell.create!(workspace: workspace, db_row: beta, db_property: revenue_property, value_text: "180")
    DbCell.create!(workspace: workspace, db_row: beta, db_property: status_property, value_text: "active")
    DbCell.create!(workspace: workspace, db_row: gamma, db_property: revenue_property, value_text: "240")
    DbCell.create!(workspace: workspace, db_row: gamma, db_property: status_property, value_text: "archived")
    DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Table", view_type: :table, default: true)
    sign_in owner

    get database_path(
      workspace_slug: workspace.slug,
      id: database.id,
      split_panel: "graph",
      sort_property_id: revenue_property.id,
      sort_direction: "desc",
      filter_property_id: status_property.id,
      filter_value: "active",
      filter_operator: "eq"
    )

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    category_labels = html.css(".notae-db-graph-category-label").map do |node|
      node.at_css("title")&.text&.strip.presence || node.text.strip
    end.reject(&:blank?)

    expect(category_labels).to eq([ "Beta", "Alpha" ])
    expect(category_labels).not_to include("Gamma")
  end

  it "keeps the gantt color picker beside the status badge and aligns bars to the badge baseline" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-gantt-row {\n  align-items: end;\n}")
    expect(stylesheet).to include(".notae-db-gantt-status-swatch input[type=\"color\"] {\n  width: 1.12rem;")
    expect(stylesheet).to include("  height: 1.3rem;")
    expect(stylesheet).to include("  border-radius: 0.45rem;")
    expect(stylesheet).to include(".notae-db-gantt-bar-wrap {\n  position: absolute;\n  bottom: 0;\n  height: 1.3rem;")
  end

  it "uses explicit primary button variants instead of submit-element styling for chip buttons" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-chip-button.notae-chip-button-primary,")
    expect(stylesheet).to include("button[type=\"submit\"].notae-chip-button.notae-chip-button-primary,")
    expect(stylesheet).not_to include("button[type=\"submit\"].notae-chip-button,\ninput[type=\"submit\"].notae-chip-button,")
  end

  it "shares neutral button styling across grid and split-view controls" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("  --notae-control-height: 2.25rem;\n")
    expect(stylesheet).to include("  --notae-control-icon-size: 2.25rem;\n")
    expect(stylesheet).to include("  --notae-overlay-mobile-width: calc(100vw - env(safe-area-inset-left, 0px) - env(safe-area-inset-right, 0px) - (var(--notae-overlay-mobile-gutter) * 2));\n")
    expect(stylesheet).to include(".notae-chip-button,\n.notae-page-tab-create-button {\n  appearance: none;")
    expect(stylesheet).to include(".notae-inline-icon-button,\n.notae-db-toolbar-icon,\n.notae-comments-trigger,")
    expect(stylesheet).to include("  font-family: inherit;")
    expect(stylesheet).to include(".notae-db-template-button,\n.notae-db-toolbar-icon,\n.notae-page-tab-create-button {\n  min-height: var(--notae-control-height);")
    expect(stylesheet).not_to include(".notae-db-gantt-toolbar-form .notae-chip-button.notae-db-gantt-toolbar-button {\n  appearance: none;\n  -webkit-appearance: none;\n  text-decoration: none;\n  cursor: pointer;\n  font: inherit;")
  end

  it "makes dense mobile controls easier to tap" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-shell.is-mobile-viewport {\n    --notae-mobile-tap-target: var(--notae-mobile-tap-target-default);\n  }")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-db-toolbar-icon,\n  .notae-shell.is-mobile-viewport .notae-comments-trigger {\n    width: var(--notae-mobile-tap-target);")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-mobile-nav-button,\n  .notae-shell.is-mobile-viewport .notae-options-mobile-nav-button,\n  .notae-shell.is-mobile-viewport .notae-kalendarium-nav-buttons .notae-chip-button,")
  end

  it "keeps mobile grid menus wide enough to render labels horizontally" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-page-header-panel,\n.notae-shell.is-mobile-viewport .notae-cover-picker-panel:not(.is-embedded),\n.notae-shell.is-mobile-viewport .notae-db-inline-panel,\n.notae-shell.is-mobile-viewport .notae-db-settings-panel {\n  position: fixed;\n  left: calc(env(safe-area-inset-left, 0px) + var(--notae-overlay-mobile-gutter));\n  right: calc(env(safe-area-inset-right, 0px) + var(--notae-overlay-mobile-gutter));\n  width: var(--notae-overlay-mobile-width);")
    expect(stylesheet).to include("  max-height: var(--notae-overlay-panel-max-height);\n  box-sizing: border-box;\n  overflow-x: hidden;\n  overflow-y: auto;\n  overscroll-behavior: contain;\n  touch-action: pan-y;\n  top: var(--notae-overlay-panel-top);\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-db-row-more-panel.is-floating {\n  width: min(18rem, var(--notae-overlay-mobile-width));")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-create-menu,\n.notae-shell.is-mobile-viewport .notae-library-popover-panel,\n.notae-shell.is-mobile-viewport .notae-people-add-panel,\n.notae-shell.is-mobile-viewport .notae-page-tab-menu-panel,\n.notae-shell.is-mobile-viewport .notae-kalendarium-calendar-popover,\n.notae-shell.is-mobile-viewport .notae-kalendarium-project-popover {\n  min-width: min(18rem, var(--notae-overlay-mobile-width));")
  end

  it "shows column hover controls and persistent column styling rules in the stylesheet" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-view-pill.is-active {\n  color: var(--notae-text-strong);")
    expect(stylesheet).to include(".notae-db-progress-field {\n  display: grid;")
    expect(stylesheet).to include("@keyframes notae-db-progress-confetti-burst {")
    expect(stylesheet).to include(".notae-db-grid th:hover .notae-db-column-hover-controls,")
    expect(stylesheet).to include(".notae-db-column-hover-controls {\n  display: inline-flex;\n  align-items: center;\n  flex: 0 0 auto;\n  opacity: 0;\n  pointer-events: none;\n  position: relative;\n  z-index: 6;")
    expect(stylesheet).to include(".notae-db-column-hover-control {\n  flex-shrink: 0;\n  position: relative;\n  z-index: 7;")
    expect(stylesheet).to include(".notae-db-grid th.is-column-bold,\n.notae-db-grid td.is-column-bold {")
    expect(stylesheet).to include(".notae-db-grid th.is-column-color-blue,\n.notae-db-grid td.is-column-color-blue {")
    expect(stylesheet).to include(".notae-db-grid th.is-column-bg-sky,\n.notae-db-grid td.is-column-bg-sky {")
    expect(stylesheet).to include(".notae-db-grid-data-row.is-row-bg-lemon td {")
    expect(stylesheet).to include(".notae-db-grid td[class*=\"is-column-color-\"] .notae-db-title-input,")
    expect(stylesheet).to include(".notae-db-column-menu-rename-form {\n  margin: 0;")
    expect(stylesheet).to include(".notae-db-row-menu-section-label {")
  end

  it "keeps split-view export buttons width-stable while feedback text changes" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-db-gantt-toolbar .notae-chip-button.notae-db-gantt-toolbar-button,")
    expect(stylesheet).to include("  justify-content: center;")
    expect(stylesheet).to include("  width: 10.5rem;")
    expect(stylesheet).to include("  white-space: nowrap;")
  end

  it "shows a Gantt empty state when no row has both start and end dates" do
    owner = User.create!(email: "database-gantt-empty-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt empty", slug: "grid-gantt-empty")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "gantt")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gantt chart unavailable")
    expect(response.body).to include("Start date")
    expect(response.body).to include("End date")
  end

  it "updates a gantt task range and persists both start and end date cells" do
    owner = User.create!(email: "database-gantt-range-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt range", slug: "grid-gantt-range")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-18")
    sign_in owner

    patch gantt_range_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: {
            start_property_id: start_property.id,
            end_property_id: end_property.id,
            start_date: "2026-04-10",
            end_date: "2026-04-21"
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "start_date" => "2026-04-10",
      "end_date" => "2026-04-21"
    )
    expect(row.reload.db_cells.find_by!(db_property: start_property).value_text).to eq("2026-04-10")
    expect(row.reload.db_cells.find_by!(db_property: end_property).value_text).to eq("2026-04-21")
    expect(row.data_json["Start date"]).to eq("2026-04-10")
    expect(row.data_json["End date"]).to eq("2026-04-21")
  end

  it "stores gantt colors on the individual row instead of the shared status" do
    owner = User.create!(email: "database-gantt-row-color-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt row color", slug: "grid-gantt-row-color")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    sign_in owner

    patch database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id),
          params: {
            db_row: {
              style_action: "set_gantt_color",
              gantt_color_hex: "#12ab34"
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(row.reload.gantt_color_hex).to eq("#12AB34")
  end

  it "stores gantt status colors in the current view config" do
    owner = User.create!(email: "database-gantt-colors-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt colors", slug: "grid-gantt-colors")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    view = DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Table", view_type: :table, default: true)
    sign_in owner

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              gantt_status_colors: {
                "started" => "#123abc"
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(view.reload.config_json["gantt_status_colors"]).to eq(
      "started" => "#123ABC"
    )
  end

  it "stores graph series colors in the current view config" do
    owner = User.create!(email: "database-graph-colors-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph colors", slug: "grid-graph-colors")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    view = DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Table", view_type: :table, default: true)
    sign_in owner

    patch database_database_view_path(workspace_slug: workspace.slug, database_id: database.id, id: view.id),
          params: {
            database_view: {
              graph_series_colors: {
                revenue_property.id.to_s => "#123abc"
              }
            }
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(view.reload.config_json["graph_series_colors"]).to eq(
      revenue_property.id.to_s => "#123ABC"
    )
  end

  it "exports the gantt view as a chart pdf" do
    owner = User.create!(email: "database-gantt-pdf-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt pdf", slug: "grid-gantt-pdf")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-18")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    sign_in owner

    get export_gantt_pdf_database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "gantt")

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include(".pdf")
    expect(response.body.byteslice(0, 4)).to eq("%PDF")
    expect(response.body.bytesize).to be > 4_000
  end

  it "renders a standalone gantt embed page for Nota embeds" do
    owner = User.create!(email: "database-gantt-embed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid gantt embed", slug: "grid-gantt-embed")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")
    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-18")
    sign_in owner

    get gantt_embed_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-gantt-embed-shell")
    expect(response.body).to include("notae-db-gantt-bar-wrap")
    expect(response.body).not_to include("Copy to Nota")
    expect(response.body).not_to include("Print to PDF")
  end

  it "exports the graph view as a chart pdf" do
    owner = User.create!(email: "database-graph-pdf-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph pdf", slug: "grid-graph-pdf")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number)
    row = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    DbCell.create!(workspace: workspace, db_row: row, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: row, db_property: margin_property, value_text: "45")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "bar", "graph_show_values" => true }
    )
    sign_in owner

    get export_graph_pdf_database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include(".pdf")
    expect(response.body.byteslice(0, 4)).to eq("%PDF")
    expect(response.body.bytesize).to be > 4_000
  end

  it "exports a line graph view as a chart pdf" do
    owner = User.create!(email: "database-line-graph-pdf-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid line graph pdf", slug: "grid-line-graph-pdf")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    january = DbRow.create!(workspace: workspace, database: database, title: "January")
    february = DbRow.create!(workspace: workspace, database: database, title: "February")
    DbCell.create!(workspace: workspace, db_row: january, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: february, db_property: revenue_property, value_text: "180")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "line", "graph_show_values" => true }
    )
    sign_in owner

    get export_graph_pdf_database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.headers["Content-Disposition"]).to include(".pdf")
    expect(response.body.byteslice(0, 4)).to eq("%PDF")
    expect(response.body.bytesize).to be > 3_500
  end

  it "exports split graphs as additional pages in the graph pdf" do
    owner = User.create!(email: "database-split-graph-pdf-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid split graph pdf", slug: "grid-split-graph-pdf")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number)
    january = DbRow.create!(workspace: workspace, database: database, title: "January")
    february = DbRow.create!(workspace: workspace, database: database, title: "February")
    DbCell.create!(workspace: workspace, db_row: january, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: january, db_property: margin_property, value_text: "40")
    DbCell.create!(workspace: workspace, db_row: february, db_property: revenue_property, value_text: "180")
    DbCell.create!(workspace: workspace, db_row: february, db_property: margin_property, value_text: "55")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: { "graph_type" => "line", "graph_show_values" => true, "graph_split_series" => true }
    )
    sign_in owner

    get export_graph_pdf_database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "graph")

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    reader = PDF::Reader.new(StringIO.new(response.body))
    extracted_text = reader.pages.map(&:text).join("\n")
    normalized_compact = extracted_text.gsub(/\s+/, "")

    expect(reader.page_count).to eq(3)
    expect(extracted_text).to include("Metrics")
    expect(normalized_compact).to include("Splitgraph")
    expect(extracted_text).to include("Revenue")
    expect(extracted_text).to include("Margin")
  end

  it "renders a standalone graph embed page for Nota embeds" do
    owner = User.create!(email: "database-graph-embed-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid graph embed", slug: "grid-graph-embed")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number)
    row = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1")
    DbCell.create!(workspace: workspace, db_row: row, db_property: revenue_property, value_text: "120")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true
    )
    sign_in owner

    get graph_embed_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-graph-embed-shell")
    expect(response.body).to include("notae-db-graph-svg")
    expect(response.body).not_to include("Copy to Nota")
    expect(response.body).not_to include("Print to PDF")
  end

  it "opens task slot suggestions in the Kalendārium split and confirms a chosen slot" do
    owner = User.create!(email: "database-kal-schedule-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal schedule", slug: "grid-kal-schedule")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    busy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    sign_in owner

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-13")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: busy_calendar,
        created_by: owner,
        updated_by: owner,
        title: "Team standup",
        starts_at_utc: Time.zone.parse("2026-04-12 08:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-12 09:00:00")
      )

      expect do
        post schedule_in_kalendarium_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)
      end.not_to change(KalendariumEvent, :count)
    end

    tasks_project = workspace.kalendarium_projects.find_by!(slug: "tasks")

    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_panel: "kalendarium",
        task_row_id: row.id,
        anchor: "row_#{row.id}"
      )
    )

    current_view_id = nil
    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "kalendarium", task_row_id: row.id)

      expect(response).to have_http_status(:ok)
      current_view_id = database.reload.database_views.find_by(default: true)&.id || database.database_views.first&.id
      html = Nokogiri::HTML(response.body)
      split_iframe = html.at_css("iframe[title='Kalendārium side peek']")
      expect(split_iframe).to be_present
      expect(split_iframe["src"]).to include("view=next_7_days")
      expect(split_iframe["src"]).to include("window_start=#{Date.current}")
      expect(split_iframe["src"]).to include("task_row_id=#{row.id}")
    end

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      expect do
        post confirm_schedule_in_kalendarium_database_db_row_path(
          workspace_slug: workspace.slug,
          database_id: database.id,
          id: row.id
        ), params: {
          starts_at_local: "2026-04-13T09:00",
          ends_at_local: "2026-04-13T09:45",
          view_id: database.database_views.find_by(default: true)&.id
        }
      end.to change(KalendariumEvent, :count).by(1)
    end

    created_event = workspace.kalendarium_events.find_by!(linked_db_row: row)
    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        view_id: current_view_id,
        split_panel: "kalendarium",
        kalendarium_window_start: "2026-04-13",
        anchor: "row_#{row.id}"
      )
    )
    expect(created_event.kalendarium_project).to eq(tasks_project)
    expect(created_event.linked_db_row).to eq(row)
    expect(created_event.starts_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:00")
    expect(created_event.ends_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:45")
  end

  it "ignores hidden calendars when finding task slots from the grid action" do
    owner = User.create!(email: "database-kal-visible-cal-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal visible calendars", slug: "grid-kal-visible-calendars")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    visible_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Visible",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    hidden_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Hidden",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "local"
    )
    sign_in owner

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "week",
      date: "2026-04-13",
      calendar_filter_applied: "1",
      calendar_ids: [ visible_calendar.id ]
    )
    expect(response).to have_http_status(:ok)

    travel_to Time.zone.parse("2026-04-13 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-13")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: hidden_calendar,
        created_by: owner,
        updated_by: owner,
        title: "Hidden day block",
        starts_at_utc: Time.zone.parse("2026-04-13 09:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-13 17:00:00")
      )

      post schedule_in_kalendarium_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)
    end

    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_panel: "kalendarium",
        task_row_id: row.id,
        anchor: "row_#{row.id}"
      )
    )
    expect(flash[:alert]).to be_blank
  end

  it "allows a manually selected slot to override work-hour scheduling rules" do
    owner = User.create!(email: "database-kal-manual-override-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal manual override", slug: "grid-kal-manual-override")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    sign_in owner

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")

      expect do
        post confirm_schedule_in_kalendarium_database_db_row_path(
          workspace_slug: workspace.slug,
          database_id: database.id,
          id: row.id
        ), params: {
          starts_at_local: "2026-04-17T20:00",
          ends_at_local: "2026-04-17T20:20",
          view_id: database.database_views.find_by(default: true)&.id
        }
      end.to change(KalendariumEvent, :count).by(1)
    end

    created_event = workspace.kalendarium_events.find_by!(linked_db_row: row)
    expect(created_event.starts_at_utc.in_time_zone("UTC").strftime("%F %H:%M")).to eq("2026-04-17 20:00")
    expect(created_event.ends_at_utc.in_time_zone("UTC").strftime("%F %H:%M")).to eq("2026-04-17 20:20")
  end

  it "keeps the split Kalendārium focused on a saved future task block" do
    owner = User.create!(email: "database-kal-saved-window-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal saved window", slug: "grid-kal-saved-window")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    sign_in owner

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")

      expect do
        post confirm_schedule_in_kalendarium_database_db_row_path(
          workspace_slug: workspace.slug,
          database_id: database.id,
          id: row.id
        ), params: {
          starts_at_local: "2026-04-20T09:00",
          ends_at_local: "2026-04-20T09:20"
        }
      end.to change(KalendariumEvent, :count).by(1)
    end

    expect(response).to redirect_to(
      database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_panel: "kalendarium",
        kalendarium_window_start: "2026-04-20",
        anchor: "row_#{row.id}"
      )
    )

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      get database_path(
        workspace_slug: workspace.slug,
        id: database.id,
        split_panel: "kalendarium",
        kalendarium_window_start: "2026-04-20"
      )

      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      split_iframe = html.at_css("iframe[title='Kalendārium side peek']")
      expect(split_iframe).to be_present
      expect(split_iframe["src"]).to include("window_start=2026-04-20")

      open_full_link = html.css("a").find { |link| link.text.strip == "Open full" }
      expect(open_full_link).to be_present
      expect(open_full_link["href"]).to include("window_start=2026-04-20")

      get split_iframe["src"]

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Review roadmap")
    end
  end

  it "makes the Tasks project visible in full Kalendarium after confirming a split-scheduled task" do
    owner = User.create!(email: "database-kal-full-view-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal full view", slug: "grid-kal-full-view")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    sign_in owner

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")

      post schedule_in_kalendarium_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)
    end

    tasks_project = workspace.kalendarium_projects.find_by!(slug: "tasks")

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      get kalendarium_path(
        workspace_slug: workspace.slug,
        view: "week",
        date: "2026-04-13",
        toggle_project_id: tasks_project.id,
        project_visible: "0"
      )
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Projects (0)")
    end

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      expect do
        post confirm_schedule_in_kalendarium_database_db_row_path(
          workspace_slug: workspace.slug,
          database_id: database.id,
          id: row.id
        ), params: {
          starts_at_local: "2026-04-13T09:00",
          ends_at_local: "2026-04-13T09:20"
        }
      end.to change(KalendariumEvent, :count).by(1)
    end

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-04-13")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Projects (1)")
      expect(response.body).to include("Review roadmap")
    end
  end

  it "shifts the split Kalendārium window to the first available suggested slot when the next seven days are full" do
    owner = User.create!(email: "database-kal-shift-owner@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Grid kal shift", slug: "grid-kal-shift")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task planning")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    busy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    sign_in owner

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")

      (Date.parse("2026-04-12")..Date.parse("2026-04-18")).each do |day|
        KalendariumEvent.create!(
          workspace: workspace,
          kalendarium_calendar: busy_calendar,
          created_by: owner,
          updated_by: owner,
          title: "Busy #{day}",
          starts_at_utc: Time.zone.parse("#{day} 08:00:00"),
          ends_at_utc: Time.zone.parse("#{day} 18:00:00")
        )
      end

      post schedule_in_kalendarium_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)

      expect(response).to redirect_to(
        database_path(
          workspace_slug: workspace.slug,
          id: database.id,
          split_panel: "kalendarium",
          task_row_id: row.id,
          anchor: "row_#{row.id}"
        )
      )
      expect(flash[:notice]).to eq("Showing the next available suggested slots in Kalendarium.")

      get database_path(workspace_slug: workspace.slug, id: database.id, split_panel: "kalendarium", task_row_id: row.id)
    end

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    split_iframe = html.at_css("iframe[title='Kalendārium side peek']")
    expect(split_iframe).to be_present
    expect(split_iframe["src"]).to include("view=next_7_days")
    expect(split_iframe["src"]).to include("window_start=2026-04-20")
    expect(split_iframe["src"]).to include("task_row_id=#{row.id}")
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

  it "renders embedded databases without the full header chrome" do
    owner = User.create!(email: "database-embedded-grid-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Embedded grid preview", slug: "embedded-grid-preview")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(
      workspace: workspace,
      name: "Embedded grid",
      icon: "🧪",
      cover_preset_key: Database::COVER_PRESET_KEYS.first,
      description: "This description should stay out of the embedded preview."
    )
    DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    DbRow.create!(workspace: workspace, database: database, title: "First row")
    sign_in owner

    get database_path(workspace_slug: workspace.slug, id: database.id, embedded: 1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-shell-embedded")
    expect(response.body).not_to include("--notae-workspace-color:")
    expect(response.body).not_to include("notae-page-cover")
    expect(response.body).not_to include("notae-db-header")
    expect(response.body).not_to include("notae-db-viewbar")
    expect(response.body).to include("notae-doc-backlinks")
    expect(response.body).not_to include("Change cover")
    expect(response.body).not_to include("Add description")
    expect(response.body).to include("notae-db-grid")
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
    Databases::EnsureLinkedPageService.call(database: database, actor: owner)
    database.linked_page.update!(root_tab_title: "Overview")
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship launch")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "Done")
    DatabaseView.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: {
        "sort_property_id" => DatabaseView::NAME_SORT_KEY,
        "sort_direction" => "desc",
        "sort_mode" => "calendar"
      }
    )
    DatabaseView.create!(workspace: workspace, database: database, created_by: owner, name: "Board", view_type: :board)
    sign_in owner

    post duplicate_database_path(workspace_slug: workspace.slug, id: database.id)

    expect(response).to be_redirect
    duplicate_id = response.location.split("/").last
    duplicate = Database.find(duplicate_id)
    expect(response).to redirect_to(database_path(workspace_slug: workspace.slug, id: duplicate.id))
    expect(duplicate.name).to start_with("Ops grid (copy)")
    expect(duplicate.linked_page).to be_present
    expect(duplicate.linked_page).not_to eq(database.linked_page)
    expect(duplicate.linked_page.title).to eq(duplicate.name)
    expect(duplicate.linked_page.root_tab_title).to eq("Overview")

    copied_property = duplicate.db_properties.find_by!(name: "Status")
    copied_row = duplicate.db_rows.find_by!(title: "Ship launch")
    copied_cell = copied_row.db_cells.find_by!(db_property_id: copied_property.id)
    expect(copied_cell.value_text).to eq("Done")
    expect(duplicate.database_views.pluck(:name)).to include("Board")
    expect(duplicate.database_views.find_by!(view_type: :table).config_json).to include(
      "sort_property_id" => DatabaseView::NAME_SORT_KEY,
      "sort_direction" => "desc",
      "sort_mode" => "calendar"
    )
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
