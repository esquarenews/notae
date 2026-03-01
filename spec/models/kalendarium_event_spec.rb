require "rails_helper"

RSpec.describe KalendariumEvent, type: :model do
  def build_workspace_stack(suffix:)
    user = User.create!(email: "kal-event-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Event #{suffix}", slug: "kal-event-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    [ user, workspace, calendar ]
  end

  it "requires end time to be after start time" do
    user, workspace, calendar = build_workspace_stack(suffix: "time-range")
    starts_at = Time.current.change(usec: 0)

    event = described_class.new(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Invalid event",
      starts_at_utc: starts_at,
      ends_at_utc: starts_at,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    expect(event).not_to be_valid
    expect(event.errors[:ends_at_utc]).to include("must be after start time")
  end

  it "queues chunk reindexing after save" do
    user, workspace, calendar = build_workspace_stack(suffix: "reindex")
    allow(Search::IndexKalendariumEventJob).to receive(:perform_later)

    event = described_class.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Kickoff",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    event.update!(title: "Kickoff updated")

    expect(Search::IndexKalendariumEventJob).to have_received(:perform_later).with(event.id).at_least(:once)
  end

  it "removes indexed chunks when destroyed" do
    user, workspace, calendar = build_workspace_stack(suffix: "destroy")
    event = described_class.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Cleanup",
      starts_at_utc: 2.days.from_now,
      ends_at_utc: 2.days.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT,
      source_id: event.id,
      kalendarium_event: event,
      chunk_index: 0,
      text: "Cleanup event details",
      token_count: 3,
      content_hash: "kal-event-destroy-hash"
    )

    expect do
      event.destroy!
    end.to change { SearchChunk.where(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_id: event.id).count }.from(1).to(0)
  end
end
