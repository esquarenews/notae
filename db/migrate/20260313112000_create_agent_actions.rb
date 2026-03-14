class CreateAgentActions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_actions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :approved_by, type: :uuid, foreign_key: { to_table: :users }
      t.references :rejected_by, type: :uuid, foreign_key: { to_table: :users }
      t.string :proposed_by, null: false, default: "manual"
      t.string :target_system, null: false
      t.string :draft_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :title, null: false
      t.boolean :approval_required, null: false, default: true
      t.boolean :dry_run, null: false, default: true
      t.jsonb :payload_json, null: false, default: {}
      t.jsonb :result_json, null: false, default: {}
      t.jsonb :policy_evaluation_json, null: false, default: {}
      t.jsonb :metadata_json, null: false, default: {}
      t.datetime :approved_at
      t.datetime :rejected_at
      t.datetime :executed_at
      t.timestamps
    end

    add_index :agent_actions, [ :workspace_id, :status, :created_at ], name: "idx_agent_actions_on_workspace_status_created_at"
    add_index :agent_actions, [ :user_id, :created_at ], name: "idx_agent_actions_on_user_created_at"
    add_index :agent_actions, [ :target_system, :draft_type ], name: "idx_agent_actions_on_system_and_type"

    create_table :agent_action_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :agent_action, null: false, type: :uuid, foreign_key: true
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :actor, type: :uuid, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.integer :sequence_number, null: false
      t.text :comment
      t.jsonb :details_json, null: false, default: {}
      t.string :previous_entry_hash
      t.string :entry_hash, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end

    add_index :agent_action_events, [ :agent_action_id, :sequence_number ], unique: true, name: "idx_agent_action_events_on_action_and_sequence"
    add_index :agent_action_events, [ :workspace_id, :created_at ], name: "idx_agent_action_events_on_workspace_created_at"
    add_index :agent_action_events, [ :event_type, :created_at ], name: "idx_agent_action_events_on_type_created_at"
  end
end
