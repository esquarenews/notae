class AddNotificationPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :meeting_notify_join_transcribing, :boolean, null: false, default: false
    add_column :users, :meeting_notify_transcribed, :boolean, null: false, default: true
    add_column :users, :meeting_notify_summarized, :boolean, null: false, default: false
    add_column :users, :slack_notification_preference, :string, null: false, default: "off"
    add_column :users, :discord_notification_preference, :string, null: false, default: "off"
    add_column :users, :email_notify_activity, :boolean, null: false, default: true
    add_column :users, :email_notify_always_send, :boolean, null: false, default: false
    add_column :users, :email_notify_page_updates, :boolean, null: false, default: true
    add_column :users, :email_notify_workspace_digest, :boolean, null: false, default: true
  end
end
