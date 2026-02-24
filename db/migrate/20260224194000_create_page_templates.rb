class CreatePageTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :page_templates, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.jsonb :snapshot_json, null: false, default: {}

      t.timestamps
    end

    add_index :page_templates, %i[workspace_id created_at]
    add_index :page_templates, %i[workspace_id name], unique: true
  end
end
