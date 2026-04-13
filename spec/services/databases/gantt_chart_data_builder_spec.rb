require "rails_helper"

RSpec.describe Databases::GanttChartDataBuilder do
  def cells_by_key_for(*rows)
    DbCell.where(db_row_id: rows.flatten.map(&:id)).includes(:db_property).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
  end

  it "builds gantt rows from task template dates and prefers row-specific colors over status colors" do
    owner = User.create!(email: "gantt-builder-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt Builder", slug: "gantt-builder")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row_one = DbRow.create!(workspace: workspace, database: database, title: "Plan launch")
    row_two = DbRow.create!(workspace: workspace, database: database, title: "Wrap handover")

    DbCell.create!(workspace: workspace, db_row: row_one, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row_one, db_property: end_property, value_text: "2026-04-15")
    DbCell.create!(workspace: workspace, db_row: row_one, db_property: status_property, value_text: "started")
    DbCell.create!(workspace: workspace, db_row: row_two, db_property: start_property, value_text: "2026-04-14")
    DbCell.create!(workspace: workspace, db_row: row_two, db_property: end_property, value_text: "2026-04-19")
    DbCell.create!(workspace: workspace, db_row: row_two, db_property: status_property, value_text: "done")
    row_one.apply_row_style_action!(action: "set_gantt_color", gantt_color_hex: "#ff66aa")
    row_one.save!

    result = described_class.new(
      rows: [ row_one, row_two ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: cells_by_key_for(row_one, row_two),
      view_config: { "gantt_status_colors" => { "started" => "#123abc" } }
    ).call

    expect(result).to be_eligible
    expect(result.start_property.name).to eq("Date created")
    expect(result.end_property.name).to eq("Due date")
    expect(result.scale).to eq("day")
    expect(result.tasks.map(&:title)).to eq([ "Plan launch", "Wrap handover" ])
    expect(result.tasks.find { |task| task.title == "Plan launch" }&.color_hex).to eq("#FF66AA")
    expect(result.tasks.find { |task| task.title == "Wrap handover" }&.color_hex).to eq("#6B7280")
  end

  it "keeps a row-specific gantt color when the status changes" do
    owner = User.create!(email: "gantt-builder-color-lock-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt Builder Color Lock", slug: "gantt-builder-color-lock")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Plan launch")

    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-15")
    status_cell = DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
    row.apply_row_style_action!(action: "set_gantt_color", gantt_color_hex: "#00aa88")
    row.save!

    first_result = described_class.new(
      rows: [ row ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: cells_by_key_for(row)
    ).call

    expect(first_result.tasks.first.color_hex).to eq("#00AA88")

    status_cell.update!(value_text: "done")

    second_result = described_class.new(
      rows: [ row.reload ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: cells_by_key_for(row)
    ).call

    expect(second_result.tasks.first.status_label).to eq("done")
    expect(second_result.tasks.first.color_hex).to eq("#00AA88")
  end

  it "returns an unavailable result when no row has both dates" do
    owner = User.create!(email: "gantt-builder-empty-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt Builder Empty", slug: "gantt-builder-empty")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Plan launch")

    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")

    result = described_class.new(
      rows: [ row ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: cells_by_key_for(row)
    ).call

    expect(result).not_to be_eligible
    expect(result.message).to include("Start date")
    expect(result.message).to include("End date")
  end

  it "switches to weekly ticks for longer ranges" do
    owner = User.create!(email: "gantt-builder-week-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt Builder Week", slug: "gantt-builder-week")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Release train")

    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-01-01")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-02-20")

    result = described_class.new(
      rows: [ row ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: cells_by_key_for(row)
    ).call

    expect(result).to be_eligible
    expect(result.scale).to eq("week")
    expect(result.ticks.size).to be > 1
    expect(result.tasks.first.length_days).to eq(51)
  end
end
