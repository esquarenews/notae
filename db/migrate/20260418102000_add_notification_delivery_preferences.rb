class AddNotificationDeliveryPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :push_notification_preferences, :jsonb, default: {}, null: false
    add_column :users, :push_quiet_hours_enabled, :boolean, default: false, null: false
    add_column :users, :push_quiet_hours_starts_at, :string, default: "22:00", null: false
    add_column :users, :push_quiet_hours_ends_at, :string, default: "07:00", null: false

    add_column :memberships, :notification_preferences_json, :jsonb, default: {}, null: false
  end
end
