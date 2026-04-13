require "rails_helper"
require "pdf/reader"

RSpec.describe Databases::GanttPdfExportService do
  it "renders a binary pdf for an eligible gantt chart" do
    owner = User.create!(email: "gantt-pdf-service-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Gantt Pdf Service", slug: "gantt-pdf-service")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, created_by: owner, name: "Roadmap")
    start_property = DbProperty.create!(workspace: workspace, database: database, name: "Start date", property_type: :date)
    end_property = DbProperty.create!(workspace: workspace, database: database, name: "End date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Ship beta")

    DbCell.create!(workspace: workspace, db_row: row, db_property: start_property, value_text: "2026-04-12")
    DbCell.create!(workspace: workspace, db_row: row, db_property: end_property, value_text: "2026-04-18")
    DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")

    gantt_data = Databases::GanttChartDataBuilder.new(
      rows: [ row ],
      db_properties: database.db_properties.ordered.to_a,
      cells_by_key: DbCell.where(db_row_id: row.id).index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    ).call

    result = described_class.call(database: database, gantt_data: gantt_data)

    expect(result.pdf.byteslice(0, 4)).to eq("%PDF")
    expect(result.pdf.bytesize).to be > 5_000

    reader = PDF::Reader.new(StringIO.new(result.pdf))
    extracted_text = reader.pages.map(&:text).join("\n")
    normalized_text = extracted_text.gsub(/\s+/, " ").strip
    normalized_compact = extracted_text.gsub(/\s+/, "").downcase
    expect(normalized_text).to include("Roadmap")
    expect(normalized_text).to include("started")
    expect(normalized_compact).to include("shipbeta")
  end
end
