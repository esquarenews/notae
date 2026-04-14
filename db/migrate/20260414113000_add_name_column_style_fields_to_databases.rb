class AddNameColumnStyleFieldsToDatabases < ActiveRecord::Migration[8.1]
  def change
    add_column :databases, :name_column_text_bold, :boolean, null: false, default: false
    add_column :databases, :name_column_text_italic, :boolean, null: false, default: false
    add_column :databases, :name_column_text_color, :string, null: false, default: "default"
  end
end
