require "rails_helper"

RSpec.describe PageExport, type: :model do
  it "generates a URL-safe token with at least 32 bytes of entropy and default expiry" do
    owner = User.create!(email: "page-export-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export workspace", slug: "page-export-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Exportable page")

    page_export = described_class.create!(workspace: workspace, page: page, requested_by: owner)
    decoded = Base64.urlsafe_decode64(page_export.token + ("=" * ((4 - (page_export.token.length % 4)) % 4)))

    expect(page_export.workspace_id).to eq(workspace.id)
    expect(decoded.bytesize).to be >= 32
    expect(page_export.expires_at).to be > 20.minutes.from_now
    expect(page_export.status).to eq("pending")
    expect(page_export).to be_active
  end

  it "tracks readiness and expiration for downloads" do
    owner = User.create!(email: "page-export-ready-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Page export ready workspace", slug: "page-export-ready-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Exportable page")
    page_export = described_class.create!(workspace: workspace, page: page, requested_by: owner)

    expect(page_export).not_to be_downloadable

    page_export.update!(status: :ready, expires_at: 1.minute.ago)

    expect(page_export.reload).to be_expired
    expect(page_export).not_to be_active
    expect(page_export).not_to be_downloadable
  end
end
