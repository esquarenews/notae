require "rails_helper"

RSpec.describe Databases::GraphChartDataBuilder do
  it "builds visible numeric series with padded graph bounds and row-based pie slices" do
    owner = User.create!(email: "database-graph-builder-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Graph builder", slug: "graph-builder")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number, position: 1024)
    profit_property = DbProperty.create!(workspace: workspace, database: database, name: "Profit", property_type: :number, position: 2048)
    notes_property = DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text, position: 3072)

    q1 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 1 with a long label")
    q2 = DbRow.create!(workspace: workspace, database: database, title: "Quarter 2")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: revenue_property, value_text: "120")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: profit_property, value_text: "45")
    DbCell.create!(workspace: workspace, db_row: q1, db_property: notes_property, value_text: "steady")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: revenue_property, value_text: "60")
    DbCell.create!(workspace: workspace, db_row: q2, db_property: profit_property, value_text: "15")

    result = described_class.new(
      rows: [ q1, q2 ],
      db_properties: [ revenue_property, profit_property, notes_property ],
      cells_by_key: DbCell.where(db_row_id: [ q1.id, q2.id ]).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] },
      view_config: {
        "graph_type" => "pie",
        "graph_show_values" => true,
        "graph_series_colors" => {
          revenue_property.id.to_s => "#123456"
        }
      }
    ).call

    expect(result).to be_eligible
    expect(result.chart_type).to eq("pie")
    expect(result.show_values).to eq(true)
    expect(result.categories.map(&:short_label).first).to end_with("…")
    expect(result.series.map(&:name)).to eq([ "Revenue", "Profit" ])
    expect(result.series.first.color_hex).to eq("#123456")
    expect(result.display_min).to eq(0.0)
    expect(result.display_max).to be > 120
    expect(result.pie_slices.map(&:name)).to eq([ "Quarter 1 with a long label", "Quarter 2" ])
    expect(result.pie_slices.sum(&:percentage)).to be_within(0.01).of(100.0)
    expect(result.pie_slices.map(&:color_hex).uniq.length).to eq(2)
    expect(result.pie_slices.map { |slice| described_class.format_percentage(slice.percentage) }).to all(include("%"))
  end

  it "computes stats trend colors and ignores custom series colors" do
    expect(described_class.stats_segment_color(10, 20)).to eq(Databases::GraphChartDataBuilder::STATS_ASCENDING_COLOR)
    expect(described_class.stats_segment_color(20, 20)).to eq(Databases::GraphChartDataBuilder::STATS_NON_ASCENDING_COLOR)
    expect(described_class.stats_segment_color(20, 10)).to eq(Databases::GraphChartDataBuilder::STATS_NON_ASCENDING_COLOR)

    owner = User.create!(email: "database-graph-builder-stats-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Graph builder stats", slug: "graph-builder-stats")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number, position: 1024)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number, position: 2048)

    monday = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    tuesday = DbRow.create!(workspace: workspace, database: database, title: "Tuesday")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: revenue_property, value_text: "100")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: margin_property, value_text: "50")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: revenue_property, value_text: "140")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: margin_property, value_text: "50")

    result = described_class.new(
      rows: [ monday, tuesday ],
      db_properties: [ revenue_property, margin_property ],
      cells_by_key: DbCell.where(db_row_id: [ monday.id, tuesday.id ]).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] },
      view_config: {
        "graph_type" => "stats",
        "graph_series_colors" => {
          revenue_property.id.to_s => "#123456",
          margin_property.id.to_s => "#00AA00"
        }
      }
    ).call

    expect(result).to be_eligible
    expect(result.chart_type).to eq("stats")
    expect(result).to be_stats
    expect(result).to be_line_like
    expect(result.series.map(&:color_hex)).to eq([
      Databases::GraphChartDataBuilder::STATS_ASCENDING_COLOR,
      Databases::GraphChartDataBuilder::STATS_NON_ASCENDING_COLOR
    ])
  end

  it "builds split series graph data with independent scales when requested" do
    owner = User.create!(email: "database-graph-builder-split-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Graph builder split", slug: "graph-builder-split")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    revenue_property = DbProperty.create!(workspace: workspace, database: database, name: "Revenue", property_type: :number, position: 1024)
    margin_property = DbProperty.create!(workspace: workspace, database: database, name: "Margin", property_type: :number, position: 2048)

    monday = DbRow.create!(workspace: workspace, database: database, title: "Monday")
    tuesday = DbRow.create!(workspace: workspace, database: database, title: "Tuesday")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: revenue_property, value_text: "100")
    DbCell.create!(workspace: workspace, db_row: monday, db_property: margin_property, value_text: "5")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: revenue_property, value_text: "140")
    DbCell.create!(workspace: workspace, db_row: tuesday, db_property: margin_property, value_text: "7")

    result = described_class.new(
      rows: [ monday, tuesday ],
      db_properties: [ revenue_property, margin_property ],
      cells_by_key: DbCell.where(db_row_id: [ monday.id, tuesday.id ]).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] },
      view_config: {
        "graph_type" => "line",
        "graph_split_series" => true
      }
    ).call

    expect(result).to be_eligible
    expect(result).to be_split_series
    expect(result.series_graphs.length).to eq(2)
    expect(result.series_graphs.map { |entry| entry.series.name }).to eq([ "Revenue", "Margin" ])
    expect(result.series_graphs.last.display_max).to be < result.display_max
    expect(result.series_graphs.map { |entry| entry.axis_ticks.length }).to all(eq(6))
  end
end
