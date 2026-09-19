require "rails_helper"

RSpec.describe Analytics::ActivityRecorder do
  include ActiveSupport::Testing::TimeHelpers

  it "keeps workspace and surface attribution while deduplicating client retries" do
    user = User.create!(email: "activity-recorder@example.com", password: "password123")
    first_workspace = Workspace.create!(name: "First activity", slug: "first-activity")
    second_workspace = Workspace.create!(name: "Second activity", slug: "second-activity")
    Membership.create!(user: user, workspace: first_workspace, role: :member)
    Membership.create!(user: user, workspace: second_workspace, role: :member)

    travel_to Time.zone.parse("2026-07-13 10:00:25 UTC") do
      described_class.call(
        user: user,
        workspace: first_workspace,
        surface: "nota",
        bucket_started_at: "2026-07-13T10:00:00Z",
        duration_seconds: 10,
        sample_id: "sample-nota-123"
      )
      described_class.call(
        user: user,
        workspace: second_workspace,
        surface: "grid",
        bucket_started_at: "2026-07-13T10:00:10Z",
        duration_seconds: 15,
        sample_id: "sample-grid-123"
      )
      described_class.call(
        user: user,
        workspace: first_workspace,
        surface: "nota",
        bucket_started_at: "2026-07-13T10:00:00Z",
        duration_seconds: 10,
        sample_id: "sample-nota-123"
      )
    end

    buckets = AnalyticsActivityBucket.where(user: user).order(:bucket_started_at, :surface)
    expect(buckets.count).to eq(2)
    expect(buckets.pluck(:workspace_id, :surface, :duration_seconds)).to contain_exactly(
      [ first_workspace.id, "nota", 10 ],
      [ second_workspace.id, "grid", 15 ]
    )
    expect(buckets.pluck(:bucket_started_at).uniq).to eq([ Time.zone.parse("2026-07-13 10:00:00 UTC") ])
  end

  it "splits an interval that crosses a wall-clock bucket without losing seconds" do
    user = User.create!(email: "activity-recorder-split@example.com", password: "password123")
    workspace = Workspace.create!(name: "Split activity", slug: "split-activity")
    Membership.create!(user:, workspace:, role: :member)

    travel_to Time.zone.parse("2026-07-13 10:00:40 UTC") do
      result = described_class.call(
        user:,
        workspace:,
        surface: "nota",
        bucket_started_at: "2026-07-13T10:00:25Z",
        duration_seconds: 10,
        sample_id: "sample-split-123"
      )

      expect(result.buckets.map(&:duration_seconds)).to eq([ 5, 5 ])
      expect(result.buckets.map(&:segment_offset_seconds)).to eq([ 25, 0 ])
      expect(result.buckets.map(&:segment_index)).to eq([ 0, 1 ])
      expect(result.buckets.map(&:bucket_started_at)).to eq([
        Time.zone.parse("2026-07-13 10:00:00 UTC"),
        Time.zone.parse("2026-07-13 10:00:30 UTC")
      ])
    end
  end

  it "respects workspace analytics opt-out and rejects inaccessible workspaces" do
    user = User.create!(email: "activity-recorder-privacy@example.com", password: "password123")
    disabled_workspace = Workspace.create!(name: "Disabled activity", slug: "disabled-activity", analytics_enabled: false)
    inaccessible_workspace = Workspace.create!(name: "Inaccessible activity", slug: "inaccessible-activity")
    Membership.create!(user: user, workspace: disabled_workspace, role: :member)

    travel_to Time.zone.parse("2026-07-13 10:00:25") do
      result = described_class.call(
        user: user,
        workspace: disabled_workspace,
        surface: "nota",
        bucket_started_at: Time.current.iso8601,
        duration_seconds: 30
      )

      expect(result.status).to eq(:disabled)
      expect do
        described_class.call(
          user: user,
          workspace: inaccessible_workspace,
          surface: "grid",
          bucket_started_at: Time.current.iso8601,
          duration_seconds: 30
        )
      end.to raise_error(described_class::InvalidSample, /not available/)
    end

    expect(AnalyticsActivityBucket.where(user: user)).to be_empty
  end

  it "rejects stale timestamps and unknown surfaces" do
    user = User.create!(email: "activity-recorder-invalid@example.com", password: "password123")
    workspace = Workspace.create!(name: "Valid global activity", slug: "valid-global-activity")
    Membership.create!(user:, workspace:, role: :member)

    travel_to Time.zone.parse("2026-07-13 10:00:25") do
      expect do
        described_class.call(
          user: user,
          workspace: nil,
          surface: "nota",
          bucket_started_at: 3.minutes.ago.iso8601,
          duration_seconds: 30
        )
      end.to raise_error(described_class::InvalidSample, /outside/)

      expect do
        described_class.call(
          user: user,
          workspace: nil,
          surface: "raw-path",
          bucket_started_at: Time.current.iso8601,
          duration_seconds: 30
        )
      end.to raise_error(described_class::InvalidSample, /Unknown/)
    end
  end

  it "does not record global activity when every accessible workspace has tracking off" do
    user = User.create!(email: "activity-recorder-global-off@example.com", password: "password123")
    workspace = Workspace.create!(name: "Global off", slug: "global-off", analytics_enabled: false)
    Membership.create!(user:, workspace:, role: :member)

    result = described_class.call(
      user:,
      workspace: nil,
      surface: "settings",
      bucket_started_at: Time.current.iso8601,
      duration_seconds: 10,
      sample_id: "sample-global-off"
    )

    expect(result.status).to eq(:disabled)
    expect(AnalyticsActivityBucket.where(user:)).to be_empty
  end
end
