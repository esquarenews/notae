require "rails_helper"

RSpec.describe PageLink, type: :model do
  it "requires source and target pages to belong to the same workspace as the edge" do
    owner = User.create!(email: "page-link-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Links", slug: "links")
    other_workspace = Workspace.create!(name: "Other Links", slug: "other-links")
    source_page = Page.create!(workspace: workspace, created_by: owner, title: "Source")
    target_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Target")

    edge = described_class.new(workspace: workspace, source_page: source_page, target_page: target_page)

    expect(edge).not_to be_valid
    expect(edge.errors[:workspace_id]).to include("must match linked pages")
  end
end
