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
end
