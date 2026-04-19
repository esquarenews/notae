require "rails_helper"

RSpec.describe "Database template services" do
  it "captures the current grid structure and reapplies it without clearing row data" do
    owner = User.create!(email: "database-template-services-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database template services", slug: "database-template-services")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    source_database = Database.create!(workspace: workspace, created_by: owner, name: "Source grid")
    status_property = DbProperty.create!(
      workspace: workspace,
      database: source_database,
      name: "Status",
      property_type: :select,
      position: 1024,
      select_options_json: [ "not started", "started", "done" ]
    )
    due_date_property = DbProperty.create!(workspace: workspace, database: source_database, name: "Due date", property_type: :date, position: 2048)
    DatabaseView.create!(
      workspace: workspace,
      database: source_database,
      created_by: owner,
      name: "Table",
      view_type: :table,
      default: true,
      config_json: {
        "visible_property_ids" => [ status_property.id, due_date_property.id ],
        "sort_property_id" => due_date_property.id,
        "sort_direction" => "asc",
        "graph_type" => "bar",
        "graph_show_values" => true,
        "graph_series_colors" => {
          status_property.id.to_s => "#123ABC"
        },
        "column_widths" => {
          "name" => 240,
          "property_#{status_property.id}" => 180
        }
      }
    )

    template = Databases::CreateTemplateService.call(
      database: source_database,
      current_view: source_database.database_views.find_by!(default: true),
      created_by: owner,
      name: "Project tracker"
    )

    expect(template.snapshot_json["properties"].map { |property| property.values_at("name", "property_type") }).to eq(
      [
        [ "Status", "select" ],
        [ "Due date", "date" ]
      ]
    )
    expect(template.snapshot_json["properties"].first["select_options"]).to eq([ "not started", "started", "done" ])
    expect(template.snapshot_json.dig("view", "config_json", "visible_property_names")).to eq([ "Status", "Due date" ])
    expect(template.snapshot_json.dig("view", "config_json", "sort_property_name")).to eq("Due date")
    expect(template.snapshot_json.dig("view", "config_json", "graph_type")).to eq("bar")
    expect(template.snapshot_json.dig("view", "config_json", "graph_show_values")).to eq(true)
    expect(template.snapshot_json.dig("view", "config_json")).not_to have_key("graph_series_colors")

    target_database = Database.create!(workspace: workspace, created_by: owner, name: "Target grid")
    DbProperty.create!(workspace: workspace, database: target_database, name: "Existing notes", property_type: :text, position: 1024)
    row = DbRow.create!(workspace: workspace, database: target_database, title: "Keep me")

    result = Databases::ApplyTemplateService.call(database: target_database, template: template, created_by: owner)

    expect(result.view).to be_present
    expect(target_database.reload.applied_template_name).to eq("Project tracker")
    expect(target_database.database_template).to eq(template)
    expect(target_database.db_rows.count).to eq(1)
    expect(target_database.db_rows.first).to eq(row)
    expect(target_database.db_properties.order(:position).pluck(:name, :property_type)).to eq(
      [
        [ "Status", "select" ],
        [ "Due date", "date" ],
        [ "Existing notes", "text" ]
      ]
    )
    expect(target_database.db_properties.find_by!(name: "Status").select_options_list).to eq([ "not started", "started", "done" ])

    applied_view = target_database.database_views.find_by!(default: true)
    expect(applied_view.view_type).to eq("table")
    expect(applied_view.config_json["sort_direction"]).to eq("asc")
    expect(applied_view.config_json["sort_property_id"]).to eq(target_database.db_properties.find_by!(name: "Due date").id)
    expect(applied_view.config_json["graph_type"]).to eq("bar")
    expect(applied_view.config_json["graph_show_values"]).to eq(true)
    expect(applied_view.config_json).not_to have_key("graph_series_colors")
    expect(Array(applied_view.config_json["visible_property_ids"]).map(&:to_s)).to eq(
      target_database.db_properties.where(name: [ "Status", "Due date" ]).order(:position).pluck(:id).map(&:to_s)
    )
  end

  it "preserves a name sort when saving and applying a template" do
    owner = User.create!(email: "database-template-name-sort-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database template name sort", slug: "database-template-name-sort")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    source_database = Database.create!(workspace: workspace, created_by: owner, name: "Source grid")
    DatabaseView.create!(
      workspace: workspace,
      database: source_database,
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

    template = Databases::CreateTemplateService.call(
      database: source_database,
      current_view: source_database.database_views.find_by!(default: true),
      created_by: owner,
      name: "Name sorted"
    )

    expect(template.snapshot_json.dig("view", "config_json", "sort_property_name")).to eq(
      Databases::CreateTemplateService::NAME_SORT_SENTINEL
    )

    target_database = Database.create!(workspace: workspace, created_by: owner, name: "Target grid")
    result = Databases::ApplyTemplateService.call(database: target_database, template: template, created_by: owner)

    expect(result.view.config_json).to include(
      "sort_property_id" => DatabaseView::NAME_SORT_KEY,
      "sort_direction" => "desc",
      "sort_mode" => "calendar"
    )
  end
end
