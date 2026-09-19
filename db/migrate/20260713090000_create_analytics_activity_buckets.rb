class CreateAnalyticsActivityBuckets < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_activity_buckets, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true, index: false
      t.references :workspace, null: true, type: :uuid, foreign_key: true, index: false
      t.string :surface, null: false
      t.datetime :bucket_started_at, null: false
      t.integer :duration_seconds, null: false, default: 30

      t.timestamps
    end

    add_index :analytics_activity_buckets,
              [ :user_id, :bucket_started_at ],
              unique: true,
              name: "idx_analytics_activity_buckets_user_started"
    add_index :analytics_activity_buckets,
              [ :user_id, :workspace_id, :bucket_started_at ],
              name: "idx_analytics_activity_buckets_scope_started"
    add_index :analytics_activity_buckets,
              [ :user_id, :surface, :bucket_started_at ],
              name: "idx_analytics_activity_buckets_surface_started"
    add_check_constraint :analytics_activity_buckets,
                         "duration_seconds BETWEEN 1 AND 30",
                         name: "analytics_activity_bucket_duration_range"
  end
end
