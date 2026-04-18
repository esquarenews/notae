class AddApiTokenScopesAndAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :scopes_json, :jsonb, default: [ "*" ], null: false

    create_table :api_token_audit_events, id: :uuid do |t|
      t.references :api_token, null: false, foreign_key: true, type: :uuid
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :workspace, foreign_key: true, type: :uuid
      t.string :event_type, null: false
      t.string :request_method
      t.string :path
      t.string :controller_name
      t.string :action_name
      t.integer :http_status
      t.jsonb :required_scopes_json, default: [], null: false
      t.jsonb :metadata_json, default: {}, null: false
      t.timestamps
    end

    add_index :api_token_audit_events, [ :api_token_id, :created_at ]
    add_index :api_token_audit_events, [ :user_id, :created_at ]
    add_index :api_token_audit_events, [ :workspace_id, :created_at ]
    add_index :api_token_audit_events, [ :event_type, :created_at ]
  end
end
