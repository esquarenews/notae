class AddMeetingFeaturesCore < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :page_kind, :string, null: false, default: "nota"
    add_index :pages, [ :workspace_id, :page_kind, :updated_at ], name: "index_pages_on_workspace_page_kind_updated_at"

    add_column :kalendarium_events, :meeting_capture_enabled, :boolean, null: false, default: false
    add_index :kalendarium_events,
              [ :workspace_id, :meeting_capture_enabled, :starts_at_utc ],
              name: "index_kal_events_on_workspace_capture_starts_at"

    create_table :meeting_sessions, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.uuid :kalendarium_event_id
      t.uuid :page_id
      t.uuid :created_by_id, null: false
      t.uuid :updated_by_id, null: false

      t.string :title, null: false
      t.text :join_url
      t.string :capture_mode, null: false, default: "upload"
      t.string :provider, null: false, default: "local"
      t.string :status, null: false, default: "scheduled"

      t.datetime :started_at
      t.datetime :ended_at
      t.datetime :processed_at
      t.datetime :consent_warning_seen_at

      t.text :transcript_text
      t.text :summary_markdown
      t.jsonb :action_items_json, null: false, default: []
      t.text :error_message
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :meeting_sessions, [ :workspace_id, :status ]
    add_index :meeting_sessions, :kalendarium_event_id
    add_index :meeting_sessions, :created_at, order: { created_at: :desc }

    create_table :meeting_utterances, id: :uuid do |t|
      t.uuid :meeting_session_id, null: false
      t.integer :position, null: false
      t.integer :started_ms
      t.integer :ended_ms
      t.string :speaker_key, null: false
      t.string :speaker_name
      t.text :text, null: false
      t.float :confidence
      t.timestamps
    end

    add_index :meeting_utterances, [ :meeting_session_id, :position ], unique: true, name: "index_meeting_utterances_on_session_and_position"

    create_table :meeting_speaker_aliases, id: :uuid do |t|
      t.uuid :workspace_id, null: false
      t.string :speaker_fingerprint, null: false
      t.string :display_name, null: false
      t.string :email
      t.string :source, null: false, default: "manual"
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :meeting_speaker_aliases,
              [ :workspace_id, :speaker_fingerprint ],
              unique: true,
              name: "index_meeting_speaker_aliases_on_workspace_and_fingerprint"

    create_table :meeting_bot_runs, id: :uuid do |t|
      t.uuid :meeting_session_id, null: false
      t.string :provider, null: false
      t.string :status, null: false, default: "queued"
      t.string :worker_id
      t.datetime :claimed_at
      t.datetime :last_heartbeat_at
      t.datetime :finished_at
      t.text :error_message
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :meeting_bot_runs, [ :status, :created_at ], name: "index_meeting_bot_runs_on_status_created_at"
    add_index :meeting_bot_runs, :meeting_session_id

    add_foreign_key :meeting_sessions, :workspaces
    add_foreign_key :meeting_sessions, :kalendarium_events
    add_foreign_key :meeting_sessions, :pages
    add_foreign_key :meeting_sessions, :users, column: :created_by_id
    add_foreign_key :meeting_sessions, :users, column: :updated_by_id
    add_foreign_key :meeting_utterances, :meeting_sessions
    add_foreign_key :meeting_speaker_aliases, :workspaces
    add_foreign_key :meeting_bot_runs, :meeting_sessions
  end
end
