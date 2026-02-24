require "rails_helper"

RSpec.describe Api::V1::Databases::CreateService, type: :service do
  it "creates database records with workspace ownership" do
    owner = User.create!(email: "api-database-service-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Database Service", slug: "api-database-service")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    database = described_class.call(workspace: workspace, attributes: { name: "Service DB" })

    expect(database).to be_persisted
    expect(database.workspace_id).to eq(workspace.id)
    expect(database.name).to eq("Service DB")
  end
end
