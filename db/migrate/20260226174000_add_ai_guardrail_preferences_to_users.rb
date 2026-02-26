class AddAiGuardrailPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ai_search_daily_budget_usd, :decimal, precision: 12, scale: 4, null: false, default: 1.5
    add_column :users, :ai_search_semantic_rate_limit_per_minute, :integer, null: false, default: 24
    add_column :users, :ai_search_answer_rate_limit_per_minute, :integer, null: false, default: 12
  end
end
