require "rails_helper"

RSpec.describe Kalendarium::ProviderEventSyncService do
  def build_stack(suffix:)
    user = User.create!(email: "kal-provider-sync-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Provider Sync #{suffix}", slug: "kal-provider-sync-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google provider sync",
      access_token: "token"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Provider event",
      starts_at_utc: Time.zone.parse("2026-03-02 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-02 11:00:00"),
      remote_event_id: "remote-provider-event-1"
    )

    [ connection, calendar, event ]
  end

  it "uses provider adapter for upsert and delete operations" do
    connection, calendar, event = build_stack(suffix: "dispatch")
    service = described_class.new(event: event)
    adapter = instance_double(Kalendarium::Providers::GoogleAdapter, upsert_remote_event!: event, delete_remote_event!: true)
    allow(Kalendarium::Providers::GoogleAdapter).to receive(:new).with(connection: connection).and_return(adapter)

    service.upsert_remote!
    service.delete_remote!

    expect(adapter).to have_received(:upsert_remote_event!).with(calendar: calendar, event: event)
    expect(adapter).to have_received(:delete_remote_event!).with(calendar: calendar, event: event)
  end

  it "moves provider events between calendars and clears pending move metadata" do
    connection, source_calendar, event = build_stack(suffix: "move")
    target_calendar = KalendariumCalendar.create!(
      workspace: source_calendar.workspace,
      kalendarium_connection: connection,
      created_by: source_calendar.created_by,
      provider: "google",
      remote_id: "target",
      name: "Target",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false
    )
    event.update!(
      kalendarium_calendar: target_calendar,
      metadata_json: {
        "pending_provider_calendar_move" => true,
        "previous_calendar_id" => source_calendar.id,
        "previous_calendar_remote_id" => source_calendar.remote_id,
        "previous_remote_event_id" => event.remote_event_id
      }
    )
    adapter = instance_double(Kalendarium::Providers::GoogleAdapter, upsert_remote_event!: event, move_remote_event!: event)
    allow(Kalendarium::Providers::GoogleAdapter).to receive(:new).with(connection: connection).and_return(adapter)

    described_class.new(event: event).upsert_remote!

    expect(adapter).to have_received(:move_remote_event!).with(from_calendar: source_calendar, to_calendar: target_calendar, event: event)
    expect(event.reload.metadata_json["pending_provider_calendar_move"]).to be_nil
    expect(event.metadata_json["previous_remote_event_id"]).to be_nil
  end
end
