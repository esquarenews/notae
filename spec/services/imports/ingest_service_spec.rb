require "rails_helper"

RSpec.describe Imports::IngestService, type: :service do
  def uploaded_file(name, content)
    file = Tempfile.new([ File.basename(name, ".*"), File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/octet-stream", original_filename: name)
  end

  it "imports csv files into a grid with inferred property types" do
    user = User.create!(email: "imports-ingest-service@example.com", password: "password123")
    workspace = Workspace.create!(name: "Ingest service", slug: "ingest-service")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    csv = uploaded_file("tasks.csv", <<~CSV)
      Name,Estimate,Due,Done
      Launch prep,5,2026-04-01,yes
      QA,2,2026-04-03,no
    CSV

    result = described_class.call(workspace: workspace, user: user, files: [ csv ])

    expect(result.imported_page_count).to eq(0)
    expect(result.imported_database_count).to eq(1)

    database = workspace.databases.find_by!(name: "tasks")
    expect(database.database_views.find_by(default: true)&.view_type).to eq("table")

    properties = database.db_properties.ordered.to_a
    expect(properties.map(&:name)).to eq([ "Estimate", "Due", "Done" ])
    expect(properties.map(&:property_type)).to eq([ "number", "date", "checkbox" ])

    rows = database.db_rows.ordered.includes(:db_cells).to_a
    expect(rows.map(&:title)).to eq([ "Launch prep", "QA" ])
    expect(rows.first.db_cells.find { |cell| cell.db_property.name == "Estimate" }&.value_text).to eq("5")
    expect(rows.first.db_cells.find { |cell| cell.db_property.name == "Due" }&.value_text).to eq("2026-04-01")
    expect(rows.first.db_cells.find { |cell| cell.db_property.name == "Done" }&.value_text).to eq("true")
  end
end
