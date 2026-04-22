class CreateFatZebraWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :fat_zebra_webhook_events, id: :uuid do |t|
      t.string :event_name, null: false
      t.string :provider_event_id, null: false
      t.string :provider_object_id
      t.string :provider_object_type
      t.string :status, null: false, default: "received"
      t.boolean :verified, null: false, default: false
      t.string :raw_body_sha256, null: false
      t.jsonb :payload_json, null: false, default: {}
      t.jsonb :headers_json, null: false, default: {}
      t.text :processing_error
      t.datetime :processed_at

      t.timestamps
    end

    add_index :fat_zebra_webhook_events, :provider_event_id, unique: true
    add_index :fat_zebra_webhook_events, %i[event_name created_at]
    add_index :fat_zebra_webhook_events, %i[status created_at]
    add_index :fat_zebra_webhook_events, %i[provider_object_type provider_object_id], name: "idx_fat_zebra_webhook_events_on_provider_object"
  end
end
