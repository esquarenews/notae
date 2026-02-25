class AddPageHeaderCustomizations < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :icon, :string
    add_column :pages, :cover_preset_key, :string
    add_column :pages, :cover_focal_y, :integer, null: false, default: 50
  end
end
