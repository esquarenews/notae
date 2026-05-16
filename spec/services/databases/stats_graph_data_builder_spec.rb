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

    february_index = result.graph.categories.index { |category| category.label == "February 2026" }
    expect(result.graph.series.first.points[february_index].value).to eq(80.0)
    expect(result.graph.axis_ticks.map(&:label)).to include("0")
    expect(result.assigned_person).to eq("Errol")
    expect(result.division).to eq("Marketing")
    expect(result.description).to eq("Active subscribers")
  end
end
