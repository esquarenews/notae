require "rails_helper"
require "pdf/reader"

RSpec.describe Pages::PdfExportService do
  it "uses measured Prawn wrapping across pages without dropping content" do
    owner = User.create!(email: "page-pdf-wrapping-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "PDF wrapping", slug: "pdf-wrapping")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    page = Page.create!(workspace: workspace, created_by: owner, title: "Measured wrapping")
    long_text = ([ "Wide words preserve their natural glyph widths." ] * 220).join(" ") + " Final wrapping sentinel."
    Block.create!(
      workspace:,
      page:,
      created_by: owner,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          { "type" => "paragraph", "content" => [ { "type" => "text", "text" => long_text } ] }
        ]
      }
    )

    result = described_class.call(page:)
    reader = PDF::Reader.new(StringIO.new(result.pdf))
    extracted_text = reader.pages.map(&:text).join(" ").squish

    expect(reader.page_count).to be > 1
    expect(extracted_text).to start_with("Measured wrapping")
    expect(extracted_text).to include("Final wrapping sentinel.")
  end
end
