class AddSegmentOffsetToAnalyticsActivityBuckets < ActiveRecord::Migration[8.1]
  def change
    add_column :analytics_activity_buckets,
               :segment_offset_seconds,
               :integer,
               null: false,
               default: 0

    add_check_constraint :analytics_activity_buckets,
                         "segment_offset_seconds BETWEEN 0 AND 29",
                         name: "analytics_activity_bucket_offset_range"
    add_check_constraint :analytics_activity_buckets,
                         "segment_offset_seconds + duration_seconds <= 30",
                         name: "analytics_activity_bucket_segment_within_bucket"
  end
end
