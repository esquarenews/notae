require "rails_helper"

RSpec.describe Notae::ScheduledTaskStore do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Rails.cache.clear
    described_class.clear_all!
    example.run
    described_class.clear_all!
    Rails.cache.clear
  end

  it "tracks successful task runs with duration and healthy status" do
    reference_time = Time.zone.parse("2026-04-19 09:00:00")

    travel_to(reference_time) do
      result = described_class.track!("epistularium:sync_due") { :ok }

      expect(result).to eq(:ok)

      snapshot = described_class.fetch(task_name: "epistularium:sync_due", reference_time:)

      expect(snapshot).to include(
        label: "Epistularium sync timer",
        cadence_label: "Every 10 minutes",
        status: :healthy,
        consecutive_failures: 0
      )
      expect(snapshot[:last_started_at]).to eq(reference_time)
      expect(snapshot[:last_succeeded_at]).to eq(reference_time)
      expect(snapshot[:last_duration_ms]).to be >= 0.0
    end
  end

  it "flags timed tasks as drifted when they miss the heartbeat window" do
    started_at = Time.zone.parse("2026-04-19 08:30:00")
    finished_at = started_at + 2.seconds
    reference_time = started_at + 20.minutes

    described_class.record_succeeded!(
      task_name: "epistularium:sync_due",
      started_at:,
      finished_at:
    )

    snapshot = described_class.fetch(task_name: "epistularium:sync_due", reference_time:)

    expect(snapshot[:status]).to eq(:drifted)
    expect(snapshot[:last_succeeded_at]).to eq(finished_at)
  end

  it "retains failure state and error details until the next successful run" do
    started_at = Time.zone.parse("2026-04-19 09:10:00")
    finished_at = started_at + 4.seconds

    described_class.record_failed!(
      task_name: "kalendarium:dispatch_reminders",
      started_at:,
      finished_at:,
      error: StandardError.new("redis unavailable")
    )

    snapshot = described_class.fetch(task_name: "kalendarium:dispatch_reminders", reference_time: finished_at)

    expect(snapshot).to include(
      status: :failed,
      consecutive_failures: 1,
      last_error: "redis unavailable",
      last_error_class: "StandardError"
    )
    expect(snapshot[:last_failed_at]).to eq(finished_at)
  end
end
