require "rails_helper"
require "pdf/reader"

RSpec.describe Databases::GraphPdfExportService do
  it "uses Notae Sans for the unavailable graph state" do
    database = instance_double(Database, name: "Metrics")
    graph_data = double(eligible?: false, message: "Add a numeric column.")

    result = described_class.call(database:, graph_data:)
    reader = PDF::Reader.new(StringIO.new(result.pdf))
    extracted_text = reader.pages.map(&:text).join(" ")

    expect(result.pdf).to start_with("%PDF")
    expect(result.pdf).to include("NotaeSans")
    expect(reader.page_count).to eq(1)
    expect(extracted_text).to include("Metrics")
    expect(extracted_text).to include("Add a numeric column.")
  end
end
