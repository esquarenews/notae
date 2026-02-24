require "rails_helper"

RSpec.describe DatabaseView, type: :model do
  it "stores typed configuration for database views" do
    owner = User.create!(email: "database-view-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "View workspace", slug: "view-workspace")
    database = Database.create!(workspace:, name: "Tasks")

    view = described_class.create!(
      workspace: workspace,
      database: database,
      created_by: owner,
      name: "Board",
      view_type: :board,
      config_json: { "group_property_id" => "abc123" }
    )

    expect(view.view_type).to eq("board")
    expect(view.config_json["group_property_id"]).to eq("abc123")
  end

  it "supports switching the default view for a database" do
    owner = User.create!(email: "database-view-default-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "View default workspace", slug: "view-default-workspace")
    database = Database.create!(workspace:, name: "Roadmap")
    table = described_class.create!(workspace:, database:, created_by: owner, name: "Table", view_type: :table, default: true)
    board = described_class.create!(workspace:, database:, created_by: owner, name: "Board", view_type: :board, default: false)

    board.set_as_default!

    expect(board.reload.default).to eq(true)
    expect(table.reload.default).to eq(false)
  end
end
