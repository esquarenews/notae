require "rails_helper"

RSpec.describe Databases::StatsGraphDataBuilder do
  it "aggregates weekly stat entries into monthly graph periods by overlapping days" do
    owner = User.create!(email: "stats-graph-builder@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stats graph workspace", slug: "stats-graph-workspace")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    Databases::StatsTemplateService.apply!(database:)

    Databases::StatsTemplateService.save_setup!(
      database: database,
      definition_params: {},
      new_definition_params: {
        "title" => "Subscribers",
        "frequency" => "weekly_mon_sun",
        "assigned_person" => "Errol",
        "division" => "Marketing",
        "description" => "Active subscribers"
      }
    )
    definition = database.db_rows.find_by!(title: "Subscribers")
    Databases::StatsTemplateService.save_entries!(
      database: database,
      date: Date.new(2026, 1, 30),
      entry_params: { definition.id => { "value" => "70" } }
    )
    Databases::StatsTemplateService.save_entries!(
      database: database,
      date: Date.new(2026, 2, 3),
      entry_params: { definition.id => { "value" => "70" } }
    )

    result = described_class.new(
      database: database,
      definition: definition,
      date: Date.new(2026, 2, 15),
      aggregation_period: "monthly",
      period_count: 4
    ).call

    february_index = result.graph.categories.index { |category| category.label == "28 Feb 2026" }
    expect(result.graph.series.first.points[february_index].value).to eq(80.0)
    expect(result.graph.axis_ticks.map(&:label)).to include("0")
    expect(result.assigned_person).to eq("Errol")
    expect(result.division).to eq("Marketing")
    expect(result.description).to eq("Active subscribers")
  end

  it "builds buckets from an explicit start and end date range" do
    owner = User.create!(email: "stats-graph-range@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stats graph range", slug: "stats-graph-range")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    Databases::StatsTemplateService.apply!(database:)
    Databases::StatsTemplateService.save_setup!(
      database: database,
      definition_params: {},
      new_definition_params: { "title" => "Revenue", "frequency" => "weekly_mon_sun" }
    )
    definition = database.db_rows.find_by!(title: "Revenue")

    result = described_class.new(
      database: database,
      definition: definition,
      date: Date.new(2026, 5, 16),
      aggregation_period: "weekly",
      period_count: 12,
      range_start_date: "2026-05-04",
      range_end_date: "2026-05-24"
    ).call

    expect(result.period_count).to eq(3)
    expect(result.graph.categories.map(&:label)).to eq([ "10 May 2026", "17 May 2026", "24 May 2026" ])
    expect(result.range_start_date).to eq(Date.new(2026, 5, 4))
    expect(result.range_end_date).to eq(Date.new(2026, 5, 24))
  end

  it "uses the stat reporting frequency for weekly graph period ends" do
    owner = User.create!(email: "stats-graph-thursday@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stats graph Thursday", slug: "stats-graph-thursday")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Metrics")
    Databases::StatsTemplateService.apply!(database:)
    Databases::StatsTemplateService.save_setup!(
      database: database,
      definition_params: {},
      new_definition_params: { "title" => "Leads", "frequency" => "weekly_thu_2pm" }
    )
    definition = database.db_rows.find_by!(title: "Leads")
    Databases::StatsTemplateService.save_entries!(
      database: database,
      date: Date.new(2026, 5, 15),
      entry_params: { definition.id => { "value" => "12" } }
    )

    result = described_class.new(
      database: database,
      definition: definition,
      date: Date.new(2026, 5, 15),
      aggregation_period: "weekly",
      period_count: 4
    ).call

    expect(result.graph.categories.last.label).to eq("21 May 2026")
    expect(result.graph.series.first.points.last.value).to eq(12.0)
  end
end
