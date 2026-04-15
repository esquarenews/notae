require "rails_helper"

RSpec.describe Meetings::EventMatcherService do
  it "prefers a flagged event when multiple events share the same Google Meet link" do
    user = User.create!(email: "meeting-event-matcher@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting event matcher", slug: "meeting-event-matcher")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    unflagged = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Engineering sync backup",
      starts_at_utc: 45.minutes.from_now,
      ends_at_utc: 105.minutes.from_now,
      meeting_capture_enabled: false,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/shared-link" }
    )
    flagged = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Engineering sync",
      starts_at_utc: 30.minutes.from_now,
      ends_at_utc: 90.minutes.from_now,
      meeting_capture_enabled: true,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/shared-link" }
    )

    match = described_class.new(
      workspace: workspace,
      join_url: "https://meet.google.com/shared-link",
      title: "Engineering sync"
    ).call

    expect(match).to eq(flagged)
    expect(match).not_to eq(unflagged)
  end
end
