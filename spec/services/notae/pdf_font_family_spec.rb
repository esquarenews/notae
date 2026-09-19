require "rails_helper"
require "prawn"

RSpec.describe Notae::PdfFontFamily do
  it "ships and registers distinct static faces for reliable PDF styling" do
    described_class::FONT_FILES.each_value do |path|
      expect(path).to exist
      expect([ "\x00\x01\x00\x00".b, "OTTO".b ]).to include(path.binread(4))
    end

    pdf = Prawn::Document.new
    family = described_class.register(pdf)

    expect(family).to eq("Notae Sans")
    expect(pdf.font_families.fetch(family)).to eq(
      described_class::FONT_FILES.transform_values(&:to_s)
    )
  end

  it "falls back safely when the complete static family is unavailable" do
    allow(described_class).to receive(:available?).and_return(false)

    pdf = Prawn::Document.new

    expect(described_class.register(pdf)).to eq("Helvetica")
    expect(pdf.font_families).not_to have_key("Notae Sans")
  end

  it "is the single font entry point for every database PDF exporter" do
    exporter_paths = %w[
      app/services/databases/grid_pdf_export_service.rb
      app/services/databases/gantt_pdf_export_service.rb
      app/services/databases/graph_pdf_export_service.rb
    ]

    exporter_paths.each do |relative_path|
      source = Rails.root.join(relative_path).read

      expect(source).to include("pdf.font(Notae::PdfFontFamily.register(pdf))")
      expect(source).not_to include("Manrope")
    end
  end
end
