require "rails_helper"

RSpec.describe DatabaseTemplate, type: :model do
  it "inherits workspace from the source database and stores snapshot data" do
    owner = User.create!(email: "database-template-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database templates", slug: "database-templates")
    database = Database.create!(workspace: workspace, created_by: owner, name: "Source grid")

    template = described_class.create!(
      database: database,
      created_by: owner,
      name: "Project tracker",
      snapshot_json: { "properties" => [] }
    )

    expect(template.workspace_id).to eq(workspace.id)
    expect(template.snapshot_json["properties"]).to eq([])
  end
end
