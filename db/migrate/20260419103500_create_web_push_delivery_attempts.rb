class CreateWebPushDeliveryAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :web_push_delivery_attempts, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :workspace, null: true, type: :uuid, foreign_key: true
      t.references :subscription,
                   null: true,
                   type: :uuid,
                   foreign_key: { to_table: :web_push_subscriptions, on_delete: :nullify }
      t.references :notification,
                   null: true,
                   type: :uuid,
                   foreign_key: { on_delete: :nullify }
      t.string :endpoint_host, null: false
      t.string :notification_type
      t.string :title, null: false, default: ""
      t.text :body
      t.integer :status, null: false, default: 0
      t.datetime :delivered_at
      t.text :error_message, null: false, default: ""

      t.timestamps
    end

    add_index :web_push_delivery_attempts, %i[user_id created_at], name: "index_web_push_delivery_attempts_on_user_created_at"
    add_index :web_push_delivery_attempts, %i[workspace_id created_at], name: "index_web_push_delivery_attempts_on_workspace_created_at"
  end
end
