class CreateDatabaseTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :database_templates, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :database, null: true, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.jsonb :snapshot_json, null: false, default: {}

      t.timestamps
    end

    add_index :database_templates, %i[workspace_id created_at]
    add_index :database_templates, %i[workspace_id name], unique: true

    add_reference :databases, :database_template, type: :uuid, foreign_key: true
    add_column :databases, :applied_template_name, :string
  end
end
