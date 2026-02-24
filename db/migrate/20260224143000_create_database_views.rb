class CreateDatabaseViews < ActiveRecord::Migration[8.1]
  def change
    create_table :database_views, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :database, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.integer :view_type, null: false, default: 0
      t.jsonb :config_json, null: false, default: {}
      t.boolean :default, null: false, default: false

      t.timestamps
    end

    add_index :database_views, %i[database_id name], unique: true
    add_index :database_views, %i[database_id default], where: "\"default\" = true", unique: true
    add_index :database_views, %i[workspace_id database_id]
  end
end
