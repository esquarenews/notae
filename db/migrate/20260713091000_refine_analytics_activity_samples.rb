class RefineAnalyticsActivitySamples < ActiveRecord::Migration[8.1]
  def up
    add_column :analytics_activity_buckets, :sample_id, :string
    add_column :analytics_activity_buckets, :segment_index, :integer, null: false, default: 0

    execute <<~SQL.squish
      UPDATE analytics_activity_buckets
      SET sample_id = id::text
      WHERE sample_id IS NULL
    SQL

    change_column_null :analytics_activity_buckets, :sample_id, false
    remove_index :analytics_activity_buckets, name: "idx_analytics_activity_buckets_user_started"
    add_index :analytics_activity_buckets,
              [ :user_id, :sample_id, :segment_index ],
              unique: true,
              name: "idx_analytics_activity_samples_idempotency"
    add_index :analytics_activity_buckets,
              [ :user_id, :bucket_started_at ],
              name: "idx_analytics_activity_buckets_user_started"
  end

  def down
    collapse_duplicate_user_buckets!
    remove_index :analytics_activity_buckets, name: "idx_analytics_activity_samples_idempotency"
    remove_index :analytics_activity_buckets, name: "idx_analytics_activity_buckets_user_started"
    add_index :analytics_activity_buckets,
              [ :user_id, :bucket_started_at ],
              unique: true,
              name: "idx_analytics_activity_buckets_user_started"
    remove_column :analytics_activity_buckets, :segment_index
    remove_column :analytics_activity_buckets, :sample_id
  end

  private

  def collapse_duplicate_user_buckets!
    # The legacy schema permits only one row per user and wall-clock bucket.
    # Preserve capped active time in the earliest row before restoring that
    # unique index, rather than letting rollback fail on valid multi-tab data.
    # Hold writers until the replacement index exists so a live heartbeat
    # cannot recreate a duplicate between the cleanup and index creation.
    execute "LOCK TABLE analytics_activity_buckets IN SHARE ROW EXCLUSIVE MODE"

    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY user_id, bucket_started_at
                 ORDER BY created_at, id
               ) AS row_number,
               LEAST(
                 SUM(duration_seconds) OVER (PARTITION BY user_id, bucket_started_at),
                 30
               )::integer AS capped_duration
        FROM analytics_activity_buckets
      )
      UPDATE analytics_activity_buckets AS buckets
      SET duration_seconds = ranked.capped_duration
      FROM ranked
      WHERE buckets.id = ranked.id
        AND ranked.row_number = 1
    SQL

    execute <<~SQL.squish
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (
                 PARTITION BY user_id, bucket_started_at
                 ORDER BY created_at, id
               ) AS row_number
        FROM analytics_activity_buckets
      )
      DELETE FROM analytics_activity_buckets AS buckets
      USING ranked
      WHERE buckets.id = ranked.id
        AND ranked.row_number > 1
    SQL
  end
end
