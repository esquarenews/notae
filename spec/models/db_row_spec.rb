require "rails_helper"

RSpec.describe DbRow, type: :model do
  it "assigns increasing positions for rows within a database" do
    workspace = Workspace.create!(name: "Row positions", slug: "row-positions")
    database = Database.create!(workspace:, name: "Tasks")
    first = described_class.create!(workspace:, database:, title: "First")
    second = described_class.create!(workspace:, database:, title: "Second")

    expect(first.position).to be > 0
    expect(second.position).to be > first.position
  end

  it "validates linked pages stay in the same workspace" do
    owner = User.create!(email: "db-row-linked-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Row linked workspace", slug: "row-linked-workspace")
    other_workspace = Workspace.create!(name: "Row linked other workspace", slug: "row-linked-other-workspace")
    database = Database.create!(workspace:, name: "Tasks")
    local_page = Page.create!(workspace:, created_by: owner, title: "Local row page")
    remote_page = Page.create!(workspace: other_workspace, created_by: owner, title: "Remote row page")

    valid_row = described_class.new(workspace:, database:, title: "Linked", linked_page: local_page)
    invalid_row = described_class.new(workspace:, database:, title: "Linked invalid", linked_page: remote_page)

    expect(valid_row).to be_valid
    expect(invalid_row).not_to be_valid
    expect(invalid_row.errors[:linked_page_id]).to include("must belong to the same workspace")
  end
end
