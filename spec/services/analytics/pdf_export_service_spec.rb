require "rails_helper"
require "pdf/reader"

RSpec.describe Analytics::PdfExportService do
  it "renders an empty snapshot without chart or font errors" do
    user = User.create!(email: "empty-analytics-pdf@example.com", password: "password123")
    workspace = Workspace.create!(name: "Empty analytics", slug: "empty-analytics")
    Membership.create!(workspace:, user:, role: :owner)
    snapshot = Analytics::SnapshotBuilder.call(
      user:,
      workspaces: [ workspace ],
      scope: "workspace",
      date_range: Analytics::DateRange.new(params: { period: "7d" })
    )

    result = described_class.call(snapshot:)
    reader = PDF::Reader.new(StringIO.new(result.pdf))

    expect(result.pdf).to start_with("%PDF")
    expect(result.pdf).to include("/BaseFont /NotaeSans-Regular")
    expect(reader.page_count).to eq(2)
    expect(reader.pages.map(&:text).join(" ")).to include("No activity recorded")
  end

  it "renders KPI values and every workspace across paginated app-wide output" do
    user = User.create!(email: "dense-analytics-pdf@example.com", password: "password123")
    workspaces = 32.times.map do |index|
      workspace = Workspace.create!(name: "PDF Workspace #{index + 1}", slug: "pdf-workspace-#{index + 1}")
      Membership.create!(workspace:, user:, role: :member)
      workspace
    end
    started_at = 10.minutes.ago.beginning_of_minute
    AnalyticsActivityBucket::SURFACES.each_with_index do |surface, index|
      AnalyticsActivityBucket.create!(
        user:,
        workspace: workspaces[index % workspaces.length],
        surface:,
        bucket_started_at: started_at + (index * AnalyticsActivityBucket::BUCKET_SECONDS).seconds,
        duration_seconds: 30
      )
    end
    snapshot = Analytics::SnapshotBuilder.call(
      user:,
      workspaces:,
      scope: "all",
      date_range: Analytics::DateRange.new(params: { period: "7d" })
    )

    result = described_class.call(snapshot:)
    reader = PDF::Reader.new(StringIO.new(result.pdf))
    page_text = reader.pages.map(&:text)
    text = page_text.join("\n")

    expect(reader.page_count).to be >= 4
    expect(page_text).to all(satisfy { |page| page.squish.present? })
    expect(text).to include("5 min")
    expect(text).to include("Chart values:")
    expect(text).to include("Continued")
    workspaces.each { |workspace| expect(text).to include(workspace.name) }
  end
end
