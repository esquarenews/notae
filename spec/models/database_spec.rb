require "rails_helper"

RSpec.describe Database, type: :model do
  it "normalizes icon input to a short emoji value" do
    workspace = Workspace.create!(name: "Database model workspace", slug: "database-model-workspace")
    database = described_class.create!(workspace: workspace, name: "Specs", icon: " 🚀✨ ")

    expect(database.reload.icon).to eq("🚀✨")
  end

  it "preserves custom emoji icon tokens" do
    workspace = Workspace.create!(name: "Database model workspace custom", slug: "database-model-workspace-custom")
    database = nil

    Tempfile.create([ "database-custom-emoji", ".png" ]) do |file|
      file.write("fake-png-content")
      file.rewind

      emoji = workspace.custom_emojis.build(name: "Spec icon")
      emoji.image.attach(Rack::Test::UploadedFile.new(file.path, "image/png"))
      emoji.save!

      database = described_class.create!(workspace: workspace, name: "Specs", icon: emoji.icon_token)
      expect(database.reload.icon).to eq(emoji.icon_token)
    end
  end

  it "accepts blank icon and description values" do
    workspace = Workspace.create!(name: "Database model workspace 2", slug: "database-model-workspace-2")
    database = described_class.new(workspace: workspace, name: "Specs", icon: "", description: "")

    expect(database).to be_valid
  end

  it "validates font style against supported values" do
    workspace = Workspace.create!(name: "Database model workspace font", slug: "database-model-workspace-font")
    database = described_class.new(workspace: workspace, name: "Font spec", font_style: "comic")

    expect(database).not_to be_valid
    expect(database.errors[:font_style]).to include("is not included in the list")
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

  it "keeps active and archived scopes safe when archived_at is unavailable" do
    original_column_names = described_class.column_names
    allow(described_class).to receive(:column_names).and_return(original_column_names - [ "archived_at" ])

    expect(described_class.active.to_sql).not_to include("archived_at")
    expect(described_class.archived).to be_empty
  end

  it "falls back safely when optional grid columns are unavailable" do
    workspace = Workspace.create!(name: "Database model workspace legacy", slug: "database-model-workspace-legacy")
    original_column_names = described_class.column_names
    missing_optional_columns = %w[
      archived_at
      description
      icon
      cover_preset_key
      cover_focal_y
      linked_page_id
      locked
      small_text
      font_style
    ]
    allow(described_class).to receive(:column_names).and_return(original_column_names - missing_optional_columns)

    database = described_class.create!(workspace: workspace, name: "Legacy grid")
    expect(database.locked?).to eq(false)
    expect(database.small_text?).to eq(false)
    expect(database.font_style).to eq("default")
    expect(database.cover_preset_key).to be_nil
    expect(database.cover_focal_y).to eq(50)
    expect(database.description).to be_nil
  end

  it "applies persistent name column style actions" do
    workspace = Workspace.create!(name: "Database model workspace name column", slug: "database-model-workspace-name-column")
    database = described_class.create!(workspace: workspace, name: "Specs")

    database.apply_name_column_style_action!(action: "toggle_bold")
    database.apply_name_column_style_action!(action: "toggle_italic")
    database.apply_name_column_style_action!(action: "set_color", text_color: "green")
    database.apply_name_column_style_action!(action: "set_background_color", background_color: "sky")
    database.save!

    database.reload
    expect(database.name_column_text_bold?).to eq(true)
    expect(database.name_column_text_italic?).to eq(true)
    expect(database.name_column_text_color).to eq("green")
    expect(database.name_column_background_color).to eq("sky")
  end
end
