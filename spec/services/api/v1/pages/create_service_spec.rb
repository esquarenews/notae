require "rails_helper"

RSpec.describe Api::V1::Pages::CreateService, type: :service do
  it "creates pages with stable workspace and actor ownership fields" do
    owner = User.create!(email: "api-page-service-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Page Service", slug: "api-page-service")

    page = described_class.call(
      workspace: workspace,
      actor: owner,
      attributes: { title: "Service created page" }
    )

    expect(page).to be_persisted
    expect(page.workspace_id).to eq(workspace.id)
    expect(page.created_by_id).to eq(owner.id)
    expect(page.title).to eq("Service created page")
  end
end
