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
end
