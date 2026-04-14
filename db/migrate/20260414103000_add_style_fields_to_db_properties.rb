class AddStyleFieldsToDbProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :db_properties, :text_bold, :boolean, null: false, default: false
    add_column :db_properties, :text_italic, :boolean, null: false, default: false
    add_column :db_properties, :text_color, :string, null: false, default: "default"
  end
end
