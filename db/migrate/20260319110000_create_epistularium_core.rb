class CreateEpistulariumCore < ActiveRecord::Migration[8.1]
  def change
    create_table :epistularium_accounts, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.string :owner_type, null: false
      t.uuid :owner_id, null: false
      t.string :provider, null: false
      t.string :label, null: false
      t.boolean :enabled, null: false, default: true
      t.string :status, null: false, default: "connected"
      t.datetime :last_synced_at
      t.text :last_error
      t.text :sync_cursor
      t.string :remote_account_id
      t.text :access_token
      t.text :refresh_token
      t.text :provider_username
      t.text :provider_password
      t.text :oauth_client_id
      t.text :oauth_client_secret
      t.jsonb :scopes_json, null: false, default: []
      t.jsonb :settings_json, null: false, default: {}
      t.uuid :created_by_id, null: false
      t.timestamps
    end

    add_index :epistularium_accounts, [ :workspace_id, :enabled ], name: "index_epistularium_accounts_on_workspace_and_enabled"
    add_index :epistularium_accounts, [ :owner_type, :owner_id ], name: "index_epistularium_accounts_on_owner"
    add_index :epistularium_accounts,
              [ :workspace_id, :owner_type, :owner_id, :provider, :label ],
              unique: true,
              name: "index_epistularium_accounts_uniqueness"

    create_table :epistularium_messages, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :epistularium_account_id, null: false
      t.string :provider_message_id, null: false
      t.string :provider_thread_id
      t.string :internet_message_id
      t.string :mailbox, null: false, default: "inbox"
      t.string :subject, null: false, default: ""
      t.string :from_name
      t.string :from_email
      t.jsonb :to_recipients_json, null: false, default: []
      t.jsonb :cc_recipients_json, null: false, default: []
      t.jsonb :bcc_recipients_json, null: false, default: []
      t.jsonb :reply_to_recipients_json, null: false, default: []
      t.datetime :sent_at
      t.datetime :received_at
      t.boolean :unread, null: false, default: false
      t.text :body_text
      t.text :body_html
      t.text :snippet
      t.string :thread_key
      t.string :source_checksum
      t.jsonb :attachment_metadata_json, null: false, default: []
      t.jsonb :headers_json, null: false, default: {}
      t.jsonb :metadata_json, null: false, default: {}
      t.datetime :last_synced_at
      t.timestamps
    end

    add_index :epistularium_messages, [ :epistularium_account_id, :provider_message_id ],
              unique: true,
              name: "index_epistularium_messages_on_account_and_provider_id"
    add_index :epistularium_messages, [ :workspace_id, :mailbox, :received_at ],
              name: "index_epistularium_messages_on_workspace_mailbox_received_at"
    add_index :epistularium_messages, [ :workspace_id, :thread_key ], name: "index_epistularium_messages_on_workspace_and_thread_key"
    add_index :epistularium_messages, :internet_message_id

    add_reference :search_chunks, :epistularium_message, type: :uuid, foreign_key: true, index: true

    add_foreign_key :epistularium_accounts, :workspaces
    add_foreign_key :epistularium_accounts, :users, column: :created_by_id
    add_foreign_key :epistularium_messages, :workspaces
    add_foreign_key :epistularium_messages, :epistularium_accounts
  end
end
