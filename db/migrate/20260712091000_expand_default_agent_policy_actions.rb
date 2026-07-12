class ExpandDefaultAgentPolicyActions < ActiveRecord::Migration[8.1]
  LEGACY_DEFAULT = %w[create_nota create_task create_calendar_event].freeze
  EXPANDED_DEFAULT = %w[create_nota update_nota create_task create_calendar_event create_database].freeze

  def up
    execute <<~SQL.squish
      UPDATE agent_policies
      SET allowed_internal_actions_json = '#{EXPANDED_DEFAULT.to_json}'::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE allowed_internal_actions_json = '#{LEGACY_DEFAULT.to_json}'::jsonb
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE agent_policies
      SET allowed_internal_actions_json = '#{LEGACY_DEFAULT.to_json}'::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE allowed_internal_actions_json = '#{EXPANDED_DEFAULT.to_json}'::jsonb
    SQL
  end
end
