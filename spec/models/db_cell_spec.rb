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

  it "normalizes checkbox values to true/false" do
    workspace = Workspace.create!(name: "Cell checkbox", slug: "cell-checkbox")
    database = Database.create!(workspace:, name: "Tasks")
    db_property = DbProperty.create!(workspace:, database:, name: "Done", property_type: :checkbox)
    db_row = DbRow.create!(workspace:, database:, title: "Write docs")

    db_cell = described_class.create!(workspace:, db_row:, db_property:, value_text: "on")
    expect(db_cell.value_text).to eq("true")

    db_cell.update!(value_text: "no")
    expect(db_cell.reload.value_text).to eq("false")
  end

  it "normalizes valid date values and rejects invalid dates" do
    workspace = Workspace.create!(name: "Cell date", slug: "cell-date")
    database = Database.create!(workspace:, name: "Tasks")
    db_property = DbProperty.create!(workspace:, database:, name: "Due", property_type: :date)
    db_row = DbRow.create!(workspace:, database:, title: "Date row")

    db_cell = described_class.create!(workspace:, db_row:, db_property:, value_text: "2026-3-7")
    expect(db_cell.value_text).to eq("2026-03-07")

    invalid_cell = described_class.new(workspace:, db_row:, db_property:, value_text: "2026-99-99")
    expect(invalid_cell).not_to be_valid
    expect(invalid_cell.errors[:value_text]).to include("must be a valid date")
  end

  it "rejects invalid number values for number properties" do
    workspace = Workspace.create!(name: "Cell number", slug: "cell-number")
    database = Database.create!(workspace:, name: "Tasks")
    db_property = DbProperty.create!(workspace:, database:, name: "Estimate", property_type: :number)
    db_row = DbRow.create!(workspace:, database:, title: "Number row")

    valid_cell = described_class.new(workspace:, db_row:, db_property:, value_text: "12.5")
    expect(valid_cell).to be_valid

    invalid_cell = described_class.new(workspace:, db_row:, db_property:, value_text: "12a")
    expect(invalid_cell).not_to be_valid
    expect(invalid_cell.errors[:value_text]).to include("must be a valid number")
  end

  it "normalizes and clamps progress values to whole steps between 0 and 10" do
    workspace = Workspace.create!(name: "Cell progress", slug: "cell-progress")
    database = Database.create!(workspace:, name: "Tasks")
    db_property = DbProperty.create!(workspace:, database:, name: "Progress", property_type: :progress)
    db_row = DbRow.create!(workspace:, database:, title: "Progress row")

    db_cell = described_class.create!(workspace:, db_row:, db_property:, value_text: "14")
    expect(db_cell.value_text).to eq("10")

    db_cell.update!(value_text: "-5")
    expect(db_cell.reload.value_text).to eq("0")

    invalid_cell = described_class.new(workspace:, db_row:, db_property:, value_text: "halfway")
    expect(invalid_cell).not_to be_valid
    expect(invalid_cell.errors[:value_text]).to include("must be a whole number between 0 and 10")
  end
end
