class AddSelectOptionsToDbProperties < ActiveRecord::Migration[8.1]
  def change
    add_column :db_properties, :select_options_json, :jsonb, null: false, default: []
  end
end
