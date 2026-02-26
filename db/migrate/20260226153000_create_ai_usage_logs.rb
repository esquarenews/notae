class CreateAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usage_logs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.string :operation, null: false
      t.string :model, null: false
      t.integer :prompt_tokens, null: false, default: 0
      t.integer :completion_tokens, null: false, default: 0
      t.integer :total_tokens, null: false, default: 0
      t.decimal :estimated_cost_usd, precision: 12, scale: 6, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :ai_usage_logs, %i[user_id workspace_id created_at], name: "idx_ai_usage_logs_on_user_workspace_created_at"
    add_index :ai_usage_logs, %i[workspace_id created_at], name: "idx_ai_usage_logs_on_workspace_created_at"
    add_index :ai_usage_logs, :operation
    add_index :ai_usage_logs, :model
  end
end
