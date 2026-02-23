class AddPagePermissionsAndAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :permission_mode, :integer, null: false, default: 0
    add_index :pages, %i[workspace_id permission_mode]

    create_table :page_shares, id: :uuid do |t|
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :created_by, null: false, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :page_shares, %i[page_id user_id], unique: true

    create_table :audit_events, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :auditable_type
      t.uuid :auditable_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :audit_events, %i[workspace_id created_at]
    add_index :audit_events, :action
    add_index :audit_events, %i[auditable_type auditable_id]
  end
end
