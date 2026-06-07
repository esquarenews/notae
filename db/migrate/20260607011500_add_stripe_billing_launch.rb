class AddStripeBillingLaunch < ActiveRecord::Migration[8.1]
  def change
    change_column_default :workspace_subscriptions, :billing_provider, from: "fat_zebra", to: "stripe"

    create_table :stripe_webhook_events, id: :uuid do |t|
      t.string :provider_event_id, null: false
      t.string :event_name, null: false
      t.string :provider_object_type
      t.string :provider_object_id
      t.jsonb :payload_json, null: false, default: {}
      t.string :status, null: false, default: "received"
      t.datetime :processed_at
      t.text :processing_error

      t.timestamps
    end

    add_index :stripe_webhook_events, :provider_event_id, unique: true
    add_index :stripe_webhook_events, %i[event_name created_at]
    add_index :stripe_webhook_events, %i[status created_at]
    add_index :stripe_webhook_events, %i[provider_object_type provider_object_id], name: "idx_stripe_webhook_events_on_provider_object"

    drop_table :fat_zebra_webhook_events, if_exists: true
  end
end
