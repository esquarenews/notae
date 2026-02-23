class CreateCommentsAndNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :comments, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :commentable, null: false, polymorphic: true, type: :uuid
      t.references :author, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :resolved_at
      t.references :resolved_by, type: :uuid, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :comments, %i[workspace_id created_at]
    add_index :comments, %i[commentable_type commentable_id created_at], name: "index_comments_on_commentable_lookup"

    create_table :notifications, id: :uuid do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.references :recipient, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.references :actor, null: false, type: :uuid, foreign_key: { to_table: :users }
      t.string :notification_type, null: false, default: "mention"
      t.references :notifiable, polymorphic: true, type: :uuid
      t.jsonb :metadata, null: false, default: {}
      t.datetime :read_at

      t.timestamps
    end

    add_index :notifications, %i[workspace_id recipient_id read_at], name: "index_notifications_unread_lookup"
    add_index :notifications, %i[recipient_id created_at]
    add_index :notifications, %i[notifiable_type notifiable_id], name: "index_notifications_on_notifiable_lookup"
  end
end
