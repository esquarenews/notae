class AddSaasAdminFoundation < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :super_admin, :boolean, null: false, default: false
    add_index :users, :super_admin

    add_column :workspaces, :suspended_at, :datetime
    add_column :workspaces, :suspension_reason, :text
    add_index :workspaces, :suspended_at

    create_table :workspace_subscriptions, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true, index: { unique: true }
      t.string :plan_key, null: false, default: "free"
      t.string :status, null: false, default: "trialing"
      t.string :billing_provider, null: false, default: "fat_zebra"
      t.string :provider_customer_id
      t.string :provider_subscription_id
      t.datetime :trial_ends_at
      t.datetime :current_period_ends_at
      t.jsonb :limits_json, null: false, default: {}
      t.jsonb :metadata_json, null: false, default: {}

      t.timestamps
    end

    add_index :workspace_subscriptions, %i[status plan_key]
    add_index :workspace_subscriptions, :provider_customer_id
    add_index :workspace_subscriptions, :provider_subscription_id

    create_table :admin_audit_events, id: :uuid do |t|
      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :workspace, type: :uuid, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.uuid :target_id
      t.jsonb :metadata_json, null: false, default: {}

      t.timestamps
    end

    add_index :admin_audit_events, :action
    add_index :admin_audit_events, %i[target_type target_id]
    add_index :admin_audit_events, %i[workspace_id created_at]
    add_index :admin_audit_events, %i[actor_id created_at]
  end
end
