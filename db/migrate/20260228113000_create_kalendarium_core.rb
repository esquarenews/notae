class CreateKalendariumCore < ActiveRecord::Migration[8.1]
  def change
    create_table :kalendarium_connections, id: :uuid do |t|
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
      t.text :ics_url
      t.jsonb :scopes_json, null: false, default: []
      t.jsonb :settings_json, null: false, default: {}
      t.uuid :created_by_id, null: false
      t.timestamps
    end

    add_index :kalendarium_connections, [ :workspace_id, :enabled ], name: "index_kalendarium_connections_on_workspace_and_enabled"
    add_index :kalendarium_connections, [ :owner_type, :owner_id ], name: "index_kalendarium_connections_on_owner"
    add_index :kalendarium_connections,
              [ :workspace_id, :owner_type, :owner_id, :provider, :label ],
              unique: true,
              name: "index_kalendarium_connections_uniqueness"

    create_table :kalendarium_calendars, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :kalendarium_connection_id
      t.string :provider
      t.string :remote_id
      t.string :name, null: false
      t.string :color_hex, null: false, default: "#3B82F6"
      t.boolean :enabled, null: false, default: true
      t.boolean :read_only, null: false, default: false
      t.string :time_zone, null: false, default: "UTC"
      t.boolean :default_for_projects, null: false, default: false
      t.string :source_kind, null: false, default: "local"
      t.uuid :created_by_id, null: false
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :kalendarium_calendars, [ :workspace_id, :enabled ], name: "index_kalendarium_calendars_on_workspace_and_enabled"
    add_index :kalendarium_calendars,
              [ :kalendarium_connection_id, :remote_id ],
              unique: true,
              where: "remote_id IS NOT NULL",
              name: "index_kalendarium_calendars_on_connection_and_remote_id"

    create_table :kalendarium_projects, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.string :name, null: false
      t.string :slug, null: false
      t.string :color_hex, null: false, default: "#8B5CF6"
      t.uuid :kalendarium_calendar_id
      t.uuid :linked_page_id
      t.datetime :archived_at
      t.uuid :created_by_id, null: false
      t.timestamps
    end

    add_index :kalendarium_projects, [ :workspace_id, :slug ], unique: true
    add_index :kalendarium_projects, [ :workspace_id, :archived_at ], name: "index_kalendarium_projects_on_workspace_and_archived_at"

    create_table :kalendarium_events, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :kalendarium_calendar_id, null: false
      t.uuid :kalendarium_project_id
      t.string :title, null: false
      t.text :description
      t.string :location
      t.datetime :starts_at_utc, null: false
      t.datetime :ends_at_utc, null: false
      t.boolean :all_day, null: false, default: false
      t.text :rrule
      t.string :status, null: false, default: "confirmed"
      t.string :visibility, null: false, default: "default"
      t.string :remote_event_id
      t.string :uid
      t.string :etag
      t.integer :sequence, null: false, default: 0
      t.datetime :last_synced_at
      t.string :source_kind, null: false, default: "local"
      t.uuid :linked_page_id
      t.uuid :linked_db_row_id
      t.uuid :created_by_id, null: false
      t.uuid :updated_by_id, null: false
      t.integer :reminder_offsets_minutes, null: false, default: [], array: true
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :kalendarium_events, [ :workspace_id, :starts_at_utc ], name: "index_kalendarium_events_on_workspace_and_starts_at"
    add_index :kalendarium_events, [ :kalendarium_calendar_id, :starts_at_utc ], name: "index_kalendarium_events_on_calendar_and_starts_at"
    add_index :kalendarium_events,
              [ :kalendarium_calendar_id, :remote_event_id ],
              unique: true,
              where: "remote_event_id IS NOT NULL",
              name: "index_kalendarium_events_on_calendar_and_remote_id"

    create_table :kalendarium_write_proposals, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :user_id, null: false
      t.uuid :kalendarium_event_id
      t.string :proposed_by, null: false, default: "api"
      t.string :operation, null: false
      t.jsonb :payload_json, null: false, default: {}
      t.string :status, null: false, default: "pending"
      t.datetime :applied_at
      t.datetime :rejected_at
      t.datetime :expires_at
      t.text :error_message
      t.timestamps
    end

    add_index :kalendarium_write_proposals, [ :workspace_id, :status ], name: "index_kalendarium_write_proposals_on_workspace_and_status"
    add_index :kalendarium_write_proposals, [ :user_id, :created_at ], name: "index_kalendarium_write_proposals_on_user_and_created_at"

    add_column :users, :calendar_extra_time_zones, :jsonb, null: false, default: []

    add_reference :search_chunks, :kalendarium_event, type: :uuid, foreign_key: true, index: false
    add_index :search_chunks, :kalendarium_event_id

    add_foreign_key :kalendarium_connections, :workspaces
    add_foreign_key :kalendarium_connections, :users, column: :created_by_id

    add_foreign_key :kalendarium_calendars, :workspaces
    add_foreign_key :kalendarium_calendars, :kalendarium_connections
    add_foreign_key :kalendarium_calendars, :users, column: :created_by_id

    add_foreign_key :kalendarium_projects, :workspaces
    add_foreign_key :kalendarium_projects, :kalendarium_calendars
    add_foreign_key :kalendarium_projects, :pages, column: :linked_page_id
    add_foreign_key :kalendarium_projects, :users, column: :created_by_id

    add_foreign_key :kalendarium_events, :workspaces
    add_foreign_key :kalendarium_events, :kalendarium_calendars
    add_foreign_key :kalendarium_events, :kalendarium_projects
    add_foreign_key :kalendarium_events, :pages, column: :linked_page_id
    add_foreign_key :kalendarium_events, :db_rows, column: :linked_db_row_id
    add_foreign_key :kalendarium_events, :users, column: :created_by_id
    add_foreign_key :kalendarium_events, :users, column: :updated_by_id

    add_foreign_key :kalendarium_write_proposals, :workspaces
    add_foreign_key :kalendarium_write_proposals, :users
    add_foreign_key :kalendarium_write_proposals, :kalendarium_events
  end
end
