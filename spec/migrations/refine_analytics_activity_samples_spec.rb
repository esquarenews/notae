require "rails_helper"
require Rails.root.join("db/migrate/20260713091000_refine_analytics_activity_samples").to_s

RSpec.describe RefineAnalyticsActivitySamples do
  it "collapses duplicate wall-clock buckets before restoring the legacy unique index" do
    user = User.create!(email: "analytics-migration@example.com", password: "password123")
    workspace = Workspace.create!(name: "Analytics migration", slug: "analytics-migration")
    Membership.create!(user: user, workspace: workspace, role: :member)
    started_at = Time.current.beginning_of_minute

    [ 10, 10, 11 ].each_with_index do |duration, index|
      AnalyticsActivityBucket.create!(
        user: user,
        workspace: workspace,
        surface: index.even? ? "nota" : "grid",
        bucket_started_at: started_at,
        duration_seconds: duration,
        sample_id: "rollback-sample-#{index}",
        segment_index: 0,
        created_at: Time.current + index.seconds
      )
    end
    AnalyticsActivityBucket.create!(
      user: user,
      workspace: workspace,
      surface: "ai",
      bucket_started_at: started_at + AnalyticsActivityBucket::BUCKET_SECONDS.seconds,
      duration_seconds: 7,
      sample_id: "rollback-distinct-sample",
      segment_index: 0
    )

    described_class.new.send(:collapse_duplicate_user_buckets!)

    collapsed = AnalyticsActivityBucket.where(user: user, bucket_started_at: started_at)
    expect(collapsed.count).to eq(1)
    expect(collapsed.pick(:duration_seconds)).to eq(AnalyticsActivityBucket::BUCKET_SECONDS)
    expect(AnalyticsActivityBucket.where(user: user).count).to eq(2)
  end
end
