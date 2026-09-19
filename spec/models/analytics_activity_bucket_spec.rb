require "rails_helper"

RSpec.describe AnalyticsActivityBucket, type: :model do
  it "accepts only privacy-safe surfaces and deduplicates a client sample" do
    user = User.create!(email: "activity-bucket@example.com", password: "password123")
    workspace = Workspace.create!(name: "Activity bucket", slug: "activity-bucket")
    Membership.create!(user: user, workspace: workspace, role: :member)
    started_at = Time.current.change(sec: 0)

    described_class.create!(
      user: user,
      workspace: workspace,
      surface: "nota",
      bucket_started_at: started_at,
      duration_seconds: 30,
      sample_id: "sample-first-123"
    )

    duplicate = described_class.new(
      user: user,
      workspace: workspace,
      surface: "grid",
      bucket_started_at: started_at,
      duration_seconds: 10,
      sample_id: "sample-first-123"
    )
    invalid_surface = described_class.new(
      user: user,
      surface: "secret-document-title",
      bucket_started_at: started_at + 30.seconds,
      duration_seconds: 30
    )
    overflowing_segment = described_class.new(
      user: user,
      workspace: workspace,
      surface: "nota",
      bucket_started_at: started_at + 30.seconds,
      segment_offset_seconds: 25,
      duration_seconds: 10
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:sample_id]).to be_present
    expect(invalid_surface).not_to be_valid
    expect(invalid_surface.errors[:surface]).to be_present
    expect(overflowing_segment).not_to be_valid
    expect(overflowing_segment.errors[:duration_seconds]).to be_present
  end
end
