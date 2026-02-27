class AddFontStyleToDatabases < ActiveRecord::Migration[8.1]
  def change
    add_column :databases, :font_style, :string, null: false, default: "default"
  end
end
