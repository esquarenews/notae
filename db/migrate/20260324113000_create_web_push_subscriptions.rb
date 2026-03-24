class CreateWebPushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :web_push_subscriptions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.text :endpoint, null: false
      t.text :p256dh, null: false
      t.text :auth, null: false
      t.datetime :expiration_time
      t.text :user_agent
      t.datetime :last_delivered_at
      t.datetime :last_error_at
      t.text :last_error_message

      t.timestamps
    end

    add_index :web_push_subscriptions, :endpoint, unique: true
    add_index :web_push_subscriptions, [ :user_id, :created_at ]
  end
end
