require "rails_helper"

RSpec.describe PageTemplate, type: :model do
  it "inherits workspace from source page and stores snapshot data" do
    owner = User.create!(email: "page-template-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Templates workspace", slug: "templates-workspace")
    page = Page.create!(workspace: workspace, created_by: owner, title: "Source page")

    template = described_class.create!(
      page: page,
      created_by: owner,
      name: "Release template",
      snapshot_json: { "page_title" => page.title, "blocks" => [] }
    )

    expect(template.workspace_id).to eq(workspace.id)
    expect(template.snapshot_json["page_title"]).to eq("Source page")
  end
end
