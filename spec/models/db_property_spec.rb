require "rails_helper"

RSpec.describe DbProperty, type: :model do
  it "persists property metadata for a database schema" do
    workspace = Workspace.create!(name: "Schema", slug: "schema")
    database = Database.create!(workspace:, name: "Tasks")

    status_property = described_class.create!(database:, workspace:, name: "Status", property_type: :text)
    priority_property = described_class.create!(database:, workspace:, name: "Priority", property_type: :number)

    expect(status_property.reload.workspace_id).to eq(workspace.id)
    expect(priority_property.position).to be > status_property.position
  end

  it "enforces unique property names per database" do
    workspace = Workspace.create!(name: "Schema unique", slug: "schema-unique")
    database = Database.create!(workspace:, name: "Backlog")
    described_class.create!(database:, workspace:, name: "Status", property_type: :text)

    duplicate = described_class.new(database:, workspace:, name: "status", property_type: :text)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to include("has already been taken")
  end

  it "applies persistent column style actions" do
    workspace = Workspace.create!(name: "Schema styles", slug: "schema-styles")
    database = Database.create!(workspace:, name: "Backlog")
    property = described_class.create!(database:, workspace:, name: "Status", property_type: :text)

    property.apply_column_style_action!(action: "toggle_bold")
    property.apply_column_style_action!(action: "toggle_italic")
    property.apply_column_style_action!(action: "set_color", text_color: "purple")
    property.apply_column_style_action!(action: "set_background_color", background_color: "mint")
    property.save!

    property.reload
    expect(property.column_bold?).to eq(true)
    expect(property.column_italic?).to eq(true)
    expect(property.column_text_color).to eq("purple")
    expect(property.column_background_color).to eq("mint")
  end
end
