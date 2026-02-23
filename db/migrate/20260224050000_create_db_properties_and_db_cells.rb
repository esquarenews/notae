class CreateDbPropertiesAndDbCells < ActiveRecord::Migration[8.1]
  def change
    create_table :db_properties, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :database, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.integer :property_type, null: false, default: 0
      t.integer :position, null: false, default: 1024

      t.timestamps
    end

    add_index :db_properties, %i[database_id position]
    add_index :db_properties, %i[database_id name], unique: true
    add_index :db_properties, %i[workspace_id database_id]
    add_check_constraint :db_properties, "position > 0", name: "check_db_properties_position_positive"

    create_table :db_cells, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :db_row, null: false, type: :uuid, foreign_key: true
      t.references :db_property, null: false, type: :uuid, foreign_key: true
      t.text :value_text, null: false, default: ""

      t.timestamps
    end

    add_index :db_cells, %i[db_row_id db_property_id], unique: true
    add_index :db_cells, %i[workspace_id db_row_id]
    add_index :db_cells, %i[workspace_id db_property_id]
  end
end
