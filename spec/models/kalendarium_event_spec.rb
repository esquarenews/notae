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

  it "queues chunk reindexing only for searchable changes" do
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
    expect(Search::IndexKalendariumEventJob).to have_received(:perform_later).with(event.id).once

    event.update!(last_synced_at: Time.current + 2.minutes, updated_by: user)
    expect(Search::IndexKalendariumEventJob).to have_received(:perform_later).with(event.id).once

    event.update!(title: "Kickoff updated")
    expect(Search::IndexKalendariumEventJob).to have_received(:perform_later).with(event.id).twice
  end

  it "tracks searchable field changes for reindex decisions" do
    user, workspace, calendar = build_workspace_stack(suffix: "reindex-keys")
    event = described_class.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Search keys",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    event.update!(updated_by: user, last_synced_at: Time.current + 5.minutes)
    expect(event.send(:search_chunk_reindex_required?)).to be(false)

    event.update!(description: "Updated searchable description", updated_by: user)
    expect(event.send(:search_chunk_reindex_required?)).to be(true)
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

  it "normalizes meeting metadata for invitees and join links" do
    user, workspace, calendar = build_workspace_stack(suffix: "meeting-metadata")
    event = described_class.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Standup",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 30.minutes,
      created_by: user,
      updated_by: user,
      metadata_json: {
        "meeting_join_url" => "https://meet.google.com/abc-defg-hij",
        "invitees" => [
          { "name" => "Alex", "email" => "alex@example.com", "status" => "accepted" },
          { "name" => "", "email" => "sam@example.com" },
          { "name" => "", "email" => "" }
        ]
      }
    )

    expect(event.meeting_join_url).to eq("https://meet.google.com/abc-defg-hij")
    expect(event.invitees).to eq(
      [
        { "name" => "Alex", "email" => "alex@example.com", "status" => "accepted" },
        { "email" => "sam@example.com" }
      ]
    )
  end
end
