class AddWorkflowControlsToAgentPolicies < ActiveRecord::Migration[8.1]
  def change
    add_column :agent_policies, :allow_internal_automation, :boolean, null: false, default: true
    add_column :agent_policies, :allowed_internal_actions_json, :jsonb, null: false, default: []
    add_column :agent_policies, :automation_retry_limit, :integer, null: false, default: 2
    add_column :agent_policies, :automation_confidence_threshold, :decimal, precision: 4, scale: 2, null: false, default: 0.70
  end
end
