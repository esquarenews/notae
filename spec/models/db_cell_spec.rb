require "rails_helper"

RSpec.describe DbCell, type: :model do
  it "syncs row cached json when a cell changes" do
    workspace = Workspace.create!(name: "Cell sync", slug: "cell-sync")
    database = Database.create!(workspace:, name: "Tasks")
    db_property = DbProperty.create!(workspace:, database:, name: "Status", property_type: :text)
    db_row = DbRow.create!(workspace:, database:, title: "Write tests")
    db_cell = described_class.create!(workspace:, db_row:, db_property:, value_text: "Todo")

    expect(db_row.reload.data_json).to eq({ "Status" => "Todo" })

    db_cell.update!(value_text: "Done")

    expect(db_row.reload.data_json).to eq({ "Status" => "Done" })
  end

  it "rejects cells where row and property belong to different databases" do
    workspace = Workspace.create!(name: "Cell validation", slug: "cell-validation")
    database_one = Database.create!(workspace:, name: "One")
    database_two = Database.create!(workspace:, name: "Two")
    db_row = DbRow.create!(workspace:, database: database_one, title: "Row")
    db_property = DbProperty.create!(workspace:, database: database_two, name: "Status", property_type: :text)
    invalid_cell = described_class.new(workspace:, db_row:, db_property:, value_text: "Invalid")

    expect(invalid_cell).not_to be_valid
    expect(invalid_cell.errors[:db_property_id]).to include("must belong to the same database as the row")
  end
end
