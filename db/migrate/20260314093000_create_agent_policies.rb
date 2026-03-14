class CreateAgentPolicies < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_policies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.jsonb :allowed_target_systems_json, null: false, default: []
      t.jsonb :allowed_draft_types_json, null: false, default: []
      t.jsonb :allowed_lifecycle_operations_json, null: false, default: []
      t.jsonb :author_roles_json, null: false, default: []
      t.jsonb :approver_roles_json, null: false, default: []
      t.boolean :approval_required, null: false, default: true
      t.boolean :dry_run_required, null: false, default: true
      t.decimal :max_estimated_cost_usd, precision: 10, scale: 2, null: false, default: 0.0
      t.jsonb :metadata_json, null: false, default: {}
      t.timestamps
    end
  end
end
