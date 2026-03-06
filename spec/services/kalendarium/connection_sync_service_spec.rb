require "rails_helper"

RSpec.describe Kalendarium::ConnectionSyncService do
  def build_stack(suffix:)
    user = User.create!(email: "kal-connection-sync-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Connection Sync #{suffix}", slug: "kal-connection-sync-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google sync",
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
      remote_id: "primary",
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )

    [ user, workspace, connection, calendar ]
  end

  it "retries pending provider writes after pull sync and clears pending markers when successful" do
    user, workspace, connection, calendar = build_stack(suffix: "retry-success")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Pending event",
      starts_at_utc: Time.zone.parse("2026-03-02 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-02 10:00:00"),
      source_kind: "local",
      metadata_json: {
        "pending_remote_sync" => true,
        "pending_remote_sync_error" => "Previous failure"
      }
    )

    adapter = instance_double(Kalendarium::Providers::GoogleAdapter, sync!: true)
    provider_sync = instance_double(Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    allow(Kalendarium::Providers::GoogleAdapter).to receive(:new).with(connection: connection).and_return(adapter)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).with(event: event).and_return(provider_sync)

    described_class.new(connection: connection).call

    event.reload
    connection.reload
    expect(Kalendarium::ProviderEventSyncService).to have_received(:new).with(event: event)
    expect(provider_sync).to have_received(:upsert_remote!)
    expect(event.metadata_json["pending_remote_sync"]).to be_nil
    expect(event.metadata_json["pending_remote_sync_error"]).to be_nil
    expect(connection.status).to eq("connected")
    expect(connection.last_error).to be_nil
  end

  it "marks the connection as sync_error when pending provider write retry fails" do
    user, workspace, connection, calendar = build_stack(suffix: "retry-fail")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Pending broken event",
      starts_at_utc: Time.zone.parse("2026-03-03 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-03 10:00:00"),
      source_kind: "local"
    )

    adapter = instance_double(Kalendarium::Providers::GoogleAdapter, sync!: true)
    provider_sync = instance_double(Kalendarium::ProviderEventSyncService)
    allow(provider_sync).to receive(:upsert_remote!).and_raise(RuntimeError, "Insufficient permissions")
    allow(Kalendarium::Providers::GoogleAdapter).to receive(:new).with(connection: connection).and_return(adapter)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).with(event: event).and_return(provider_sync)

    expect do
      described_class.new(connection: connection).call
    end.to raise_error(RuntimeError, /Remote write sync failed/)

    event.reload
    connection.reload
    expect(event.metadata_json["pending_remote_sync"]).to eq(true)
    expect(event.metadata_json["pending_remote_sync_error"]).to include("Insufficient permissions")
    expect(connection.status).to eq("sync_error")
    expect(connection.last_error).to include("Remote write sync failed")
  end

  it "limits retryable provider writes to the selected calendars when syncing a subset" do
    user, workspace, connection, primary_calendar = build_stack(suffix: "calendar-subset")
    secondary_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "secondary",
      name: "Secondary",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    included_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: primary_calendar,
      created_by: user,
      updated_by: user,
      title: "Included event",
      starts_at_utc: Time.zone.parse("2026-03-04 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-04 10:00:00"),
      source_kind: "local"
    )
    excluded_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: secondary_calendar,
      created_by: user,
      updated_by: user,
      title: "Excluded event",
      starts_at_utc: Time.zone.parse("2026-03-04 11:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-04 12:00:00"),
      source_kind: "local"
    )

    adapter = instance_double(Kalendarium::Providers::GoogleAdapter, sync!: true)
    included_sync = instance_double(Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    allow(Kalendarium::Providers::GoogleAdapter).to receive(:new).with(connection: connection).and_return(adapter)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).with(event: included_event).and_return(included_sync)

    described_class.new(connection: connection, calendars: [ primary_calendar ]).call

    expect(Kalendarium::ProviderEventSyncService).to have_received(:new).with(event: included_event)
    expect(Kalendarium::ProviderEventSyncService).not_to have_received(:new).with(event: excluded_event)
  end

  it "keeps an iCloud connection connected when an empty response preserves existing local events" do
    user = User.create!(email: "kal-connection-sync-icloud-empty@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Connection Sync iCloud Empty", slug: "kal-connection-sync-icloud-empty")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud sync",
      provider_username: "user@example.com",
      provider_password: "abcd-efgh-ijkl-mnop",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/home/",
      name: "Home",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true,
      enabled: true
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Keep me",
      starts_at_utc: Time.zone.parse("2026-03-08 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-08 10:00:00"),
      source_kind: "provider",
      remote_event_id: "keep-event-uid"
    )

    adapter = instance_double(Kalendarium::Providers::IcloudCaldavAdapter, sync!: true)
    allow(Kalendarium::Providers::IcloudCaldavAdapter).to receive(:new).with(connection: connection).and_return(adapter)

    expect { described_class.new(connection: connection).call }.not_to raise_error

    connection.reload
    expect(connection.status).to eq("connected")
    expect(connection.last_error).to be_nil
    expect(connection.last_synced_at).to be_present
  end
end
