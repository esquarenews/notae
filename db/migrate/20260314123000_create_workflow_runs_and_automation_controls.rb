class CreateWorkflowRunsAndAutomationControls < ActiveRecord::Migration[8.1]
  def change
    create_table :workflow_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.string :workflow_kind, null: false
      t.string :status, null: false, default: "queued"
      t.string :trigger_source, null: false, default: "manual"
      t.integer :attempts_count, null: false, default: 0
      t.integer :max_attempts, null: false, default: 2
      t.decimal :confidence_score, precision: 4, scale: 2, null: false, default: 1.0
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.datetime :cancelled_at
      t.jsonb :input_json, null: false, default: {}
      t.jsonb :plan_json, null: false, default: {}
      t.jsonb :result_json, null: false, default: {}
      t.jsonb :policy_snapshot_json, null: false, default: {}
      t.jsonb :metadata_json, null: false, default: {}
      t.text :error_message
      t.timestamps
    end

    add_index :workflow_runs, [ :workspace_id, :status, :created_at ], name: "idx_workflow_runs_on_workspace_status_created_at"
    add_index :workflow_runs, [ :user_id, :created_at ], name: "idx_workflow_runs_on_user_created_at"
    add_index :workflow_runs, [ :workflow_kind, :status ], name: "idx_workflow_runs_on_kind_status"

    create_table :automation_controls, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :scope_name, null: false
      t.boolean :enabled, null: false, default: true
      t.datetime :paused_at
      t.text :pause_reason
      t.timestamps
    end

    add_index :automation_controls, :scope_name, unique: true
  end
end
