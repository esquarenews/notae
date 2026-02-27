require "rails_helper"

RSpec.describe Database, type: :model do
  it "normalizes icon input to a short emoji value" do
    workspace = Workspace.create!(name: "Database model workspace", slug: "database-model-workspace")
    database = described_class.create!(workspace: workspace, name: "Specs", icon: " 🚀✨ ")

    expect(database.reload.icon).to eq("🚀✨")
  end

  it "accepts blank icon and description values" do
    workspace = Workspace.create!(name: "Database model workspace 2", slug: "database-model-workspace-2")
    database = described_class.new(workspace: workspace, name: "Specs", icon: "", description: "")

    expect(database).to be_valid
  end

  it "treats preset covers as a valid attached-style cover state" do
    workspace = Workspace.create!(name: "Database model workspace 3", slug: "database-model-workspace-3")
    database = described_class.create!(
      workspace: workspace,
      name: "Preset cover DB",
      cover_preset_key: described_class::COVER_PRESET_KEYS.first
    )

    expect(database.cover?).to eq(true)
    expect(database.cover_focal_y).to eq(50)
  end

  it "accepts linked pages in the same workspace and rejects cross-workspace links" do
    owner = User.create!(email: "database-linked-page-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Database linked page workspace", slug: "database-linked-page-workspace")
    other_workspace = Workspace.create!(name: "Database linked page other workspace", slug: "database-linked-page-other-workspace")
    local_page = Page.create!(workspace: workspace, created_by: owner, title: "Local page")
    remote_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Remote page")

    valid_database = described_class.new(workspace: workspace, name: "Linked DB", linked_page: local_page)
    invalid_database = described_class.new(workspace: workspace, name: "Invalid linked DB", linked_page: remote_page)

    expect(valid_database).to be_valid
    expect(invalid_database).not_to be_valid
    expect(invalid_database.errors[:linked_page_id]).to include("must belong to the same workspace")
  end
end
