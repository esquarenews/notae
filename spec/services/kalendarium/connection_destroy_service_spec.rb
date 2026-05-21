require "rails_helper"
require "digest"

RSpec.describe Kalendarium::ConnectionDestroyService do
  def build_stack(suffix:)
    user = User.create!(email: "kal-destroy-service-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Destroy Service #{suffix}", slug: "kal-destroy-service-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Destroy me",
      access_token: "token-#{suffix}",
      refresh_token: "refresh-#{suffix}",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider"
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Destroy event",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00"),
      source_kind: "provider"
    )

    [ user, workspace, connection, calendar, event ]
  end

  it "bulk-cleans calendars/events/search chunks and removes the connection" do
    user, workspace, connection, calendar, event = build_stack(suffix: "bulk-clean")
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      kalendarium_event: event,
      operation: "create",
      payload_json: { "title" => "Destroy event" },
      proposed_by: "ai_assistant",
      status: "pending"
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      name: "Project",
      slug: "destroy-project",
      color_hex: "#8B5CF6",
      kalendarium_calendar: calendar,
      created_by: user
    )
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT,
      source_id: event.id,
      kalendarium_event: event,
      chunk_index: 0,
      text: "Destroy event chunk",
      token_count: 3,
      content_hash: Digest::SHA256.hexdigest("Destroy event chunk")
    )
    meeting_session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Captured meeting",
      capture_mode: "browser_extension",
      provider: "google_meet",
      status: "completed"
    )

    described_class.new(connection: connection).call

    expect(KalendariumConnection.where(id: connection.id)).to be_empty
    expect(KalendariumCalendar.where(id: calendar.id)).to be_empty
    expect(KalendariumEvent.where(id: event.id)).to be_empty
    expect(SearchChunk.where(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_id: event.id)).to be_empty
    expect(proposal.reload.kalendarium_event_id).to be_nil
    expect(meeting_session.reload.kalendarium_event_id).to be_nil
    expect(project.reload.kalendarium_calendar_id).to be_nil
  end
end
