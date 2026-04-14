class AddBackgroundStyleFieldsToGridColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :db_properties, :background_color, :string, null: false, default: "default"
    add_column :databases, :name_column_background_color, :string, null: false, default: "default"
  end
end
