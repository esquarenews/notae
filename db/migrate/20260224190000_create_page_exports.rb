class CreatePageExports < ActiveRecord::Migration[8.1]
  def change
    create_table :page_exports, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :requested_by, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.integer :status, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :completed_at
      t.datetime :failed_at
      t.text :error_message, null: false, default: ""

      t.timestamps
    end

    add_index :page_exports, :token, unique: true
    add_index :page_exports, %i[workspace_id page_id created_at], name: "index_page_exports_on_workspace_page_created_at"
    add_index :page_exports, %i[workspace_id expires_at]
  end
end
