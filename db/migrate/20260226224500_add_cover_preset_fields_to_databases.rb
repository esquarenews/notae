class AddCoverPresetFieldsToDatabases < ActiveRecord::Migration[8.0]
  def change
    add_column :databases, :cover_preset_key, :string
    add_column :databases, :cover_focal_y, :integer, null: false, default: 50
  end
end
