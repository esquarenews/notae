class AddSaasAdminPlanFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :saas_plan_key, :string, default: "free", null: false
    add_column :users, :workspace_limit_override, :integer

    add_index :users, :saas_plan_key
  end
end
