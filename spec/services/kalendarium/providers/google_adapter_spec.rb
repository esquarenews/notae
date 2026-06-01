require "rails_helper"

RSpec.describe Kalendarium::Providers::GoogleAdapter do
  def build_stack(suffix:)
    user = User.create!(email: "kal-google-adapter-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Google Adapter #{suffix}", slug: "kal-google-adapter-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google personal",
      access_token: "google-token-#{suffix}"
    )

    [ user, workspace, connection ]
  end

  it "raises when both Google access and refresh tokens are missing" do
    _user, _workspace, connection = build_stack(suffix: "missing-creds")
    connection.update_columns(access_token: nil, refresh_token: nil)

    expect do
      described_class.new(connection: connection).sync!
    end.to raise_error(RuntimeError, "Google access token is missing or no longer decryptable. Re-authorize Google OAuth.")
  end

  it "upserts calendars/events and cancels stale provider events" do
    user, workspace, connection = build_stack(suffix: "upsert")
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Old Primary",
      color_hex: "#111111",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    stale_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "removed-calendar",
      name: "Old Removed",
      color_hex: "#222222",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true,
      enabled: true
    )
    cancelled_via_remote_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Old cancelled event",
      starts_at_utc: Time.zone.parse("2026-03-05 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-05 11:00:00"),
      source_kind: "provider",
      remote_event_id: "old-event",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    stale_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Old stale event",
      starts_at_utc: Time.zone.parse("2026-03-06 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-06 11:00:00"),
      source_kind: "provider",
      remote_event_id: "missing-event",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_all_remote_calendars).and_return(
      [
        {
          "id" => "primary",
          "summary" => "Primary",
          "backgroundColor" => "#6F4BFF",
          "timeZone" => "Australia/Melbourne",
          "accessRole" => "owner",
          "etag" => "\"etag-cal\"",
          "primary" => true
        }
      ]
    )
    allow(adapter).to receive(:fetch_calendar_events).and_return(
      [
        {
          "id" => "event-1",
          "iCalUID" => "event-uid-1@example.com",
          "summary" => "Dentist",
          "description" => "Routine checkup",
          "location" => "Clinic",
          "hangoutLink" => "https://meet.google.com/abc-defg-hij",
          "attendees" => [
            { "email" => "alex@example.com", "displayName" => "Alex", "responseStatus" => "accepted" },
            { "email" => "sam@example.com", "responseStatus" => "needsAction" }
          ],
          "status" => "confirmed",
          "visibility" => "private",
          "etag" => "\"etag-1\"",
          "sequence" => 3,
          "start" => { "dateTime" => "2026-03-03T09:00:00Z" },
          "end" => { "dateTime" => "2026-03-03T10:00:00Z" }
        },
        {
          "id" => "event-2",
          "summary" => "Public holiday",
          "status" => "tentative",
          "start" => { "date" => "2026-03-04" },
          "end" => { "date" => "2026-03-05" }
        },
        {
          "id" => "event-3",
          "eventType" => "workingLocation",
          "workingLocationProperties" => {
            "type" => "homeOffice"
          },
          "status" => "confirmed",
          "start" => { "date" => "2026-03-06" },
          "end" => { "date" => "2026-03-07" }
        },
        {
          "id" => "event-4",
          "summary" => "Malformed nested payload event",
          "conferenceData" => "unexpected string",
          "creator" => "unexpected string",
          "organizer" => "unexpected string",
          "originalStartTime" => "unexpected string",
          "status" => "confirmed",
          "start" => { "dateTime" => "2026-03-07T09:00:00Z" },
          "end" => { "dateTime" => "2026-03-07T10:00:00Z" }
        },
        {
          "id" => "old-event",
          "status" => "cancelled"
        }
      ]
    )

    adapter.sync!

    calendar.reload
    expect(calendar.name).to eq("Primary")
    expect(calendar.color_hex).to eq("#6F4BFF")
    expect(calendar.time_zone).to eq("Australia/Melbourne")
    expect(calendar.read_only).to be(false)
    expect(calendar.source_kind).to eq("provider")
    expect(calendar.metadata_json["etag"]).to eq("\"etag-cal\"")
    expect(calendar.metadata_json["primary"]).to be(true)

    imported_event = calendar.kalendarium_events.find_by(remote_event_id: "event-1")
    expect(imported_event).to be_present
    expect(imported_event.title).to eq("Dentist")
    expect(imported_event.location).to eq("Clinic")
    expect(imported_event.status).to eq("confirmed")
    expect(imported_event.visibility).to eq("private")
    expect(imported_event.etag).to eq("\"etag-1\"")
    expect(imported_event.sequence).to eq(3)
    expect(imported_event.source_kind).to eq("provider")
    expect(imported_event.metadata_json["meeting_join_url"]).to eq("https://meet.google.com/abc-defg-hij")
    expect(imported_event.metadata_json["invitees"]).to include(
      { "email" => "alex@example.com", "name" => "Alex", "status" => "accepted" },
      { "email" => "sam@example.com", "status" => "needsAction" }
    )

    all_day_event = calendar.kalendarium_events.find_by(remote_event_id: "event-2")
    expect(all_day_event).to be_present
    expect(all_day_event.all_day).to be(true)
    expect(all_day_event.status).to eq("tentative")
    expect(all_day_event.ends_at_utc - all_day_event.starts_at_utc).to eq(1.day)

    working_location_event = calendar.kalendarium_events.find_by(remote_event_id: "event-3")
    expect(working_location_event).to be_present
    expect(working_location_event.all_day).to be(true)
    expect(working_location_event.title).to eq("Working location: Home")
    expect(working_location_event.metadata_json["event_type"]).to eq("workingLocation")

    malformed_event = calendar.kalendarium_events.find_by(remote_event_id: "event-4")
    expect(malformed_event).to be_present
    expect(malformed_event.title).to eq("Malformed nested payload event")
    expect(malformed_event.metadata_json["meeting_join_url"]).to be_nil
    expect(malformed_event.metadata_json["creator_email"]).to be_nil
    expect(malformed_event.metadata_json["organizer_email"]).to be_nil
    expect(malformed_event.metadata_json["original_start_time"]).to be_nil

    expect(cancelled_via_remote_event.reload.status).to eq("cancelled")
    expect(stale_event.reload.status).to eq("cancelled")
    expect(stale_calendar.reload.enabled).to be(false)
  end

  it "requests non-default Google event types including working location" do
    _user, _workspace, connection = build_stack(suffix: "event-types")
    adapter = described_class.new(connection: connection)

    allow(adapter).to receive(:fetch_json).and_return({ "items" => [] })

    adapter.send(
      :fetch_calendar_events,
      calendar_id: "primary",
      range_start: Time.zone.parse("2026-03-01 00:00:00"),
      range_end: Time.zone.parse("2026-03-31 23:59:59")
    )

    expect(adapter).to have_received(:fetch_json).with(
      path: "/calendar/v3/calendars/primary/events",
      params: hash_including(
        conferenceDataVersion: 1,
        alwaysIncludeEmail: true,
        maxAttendees: 200,
        eventTypes: array_including("default", "workingLocation", "outOfOffice", "focusTime")
      )
    )
  end

  it "does not enqueue reindex jobs for unchanged provider events on repeat sync" do
    user, workspace, connection = build_stack(suffix: "repeat-sync-no-reindex")
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
    adapter = described_class.new(connection: connection)

    allow(adapter).to receive(:fetch_all_remote_calendars).and_return(
      [
        {
          "id" => "primary",
          "summary" => "Primary",
          "backgroundColor" => "#3B82F6",
          "timeZone" => "UTC",
          "accessRole" => "owner"
        }
      ]
    )
    stable_event_payload = [
      {
        "id" => "repeat-event",
        "summary" => "Repeat sync event",
        "status" => "confirmed",
        "start" => { "dateTime" => "2026-03-09T09:00:00Z" },
        "end" => { "dateTime" => "2026-03-09T10:00:00Z" }
      }
    ]
    allow(adapter).to receive(:fetch_calendar_events).and_return(stable_event_payload, stable_event_payload)

    queue_adapter = ActiveJob::Base.queue_adapter
    queue_adapter.enqueued_jobs.clear
    adapter.sync!
    first_sync_reindex_jobs = queue_adapter.enqueued_jobs.count { |job| job[:job] == Search::IndexKalendariumEventJob }
    expect(first_sync_reindex_jobs).to eq(1)
    expect(calendar.kalendarium_events.find_by(remote_event_id: "repeat-event")).to be_present

    queue_adapter.enqueued_jobs.clear
    adapter.sync!
    second_sync_reindex_jobs = queue_adapter.enqueued_jobs.count { |job| job[:job] == Search::IndexKalendariumEventJob }
    expect(second_sync_reindex_jobs).to eq(0)
  end

  it "creates a remote event for a provider-backed local event and persists returned identifiers" do
    user, workspace, connection = build_stack(suffix: "write-create")
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
      title: "Local provider event",
      starts_at_utc: Time.zone.parse("2026-03-12 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-12 10:00:00"),
      rrule: "FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=24",
      source_kind: "local"
    )
    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:request_json).and_return(
      {
        "id" => "remote-created-1",
        "iCalUID" => "remote-created-1@google.com",
        "etag" => "\"etag-created\"",
        "sequence" => 2,
        "status" => "confirmed",
        "visibility" => "default",
        "start" => { "dateTime" => "2026-03-12T09:00:00Z" },
        "end" => { "dateTime" => "2026-03-12T10:00:00Z" }
      }
    )

    adapter.upsert_remote_event!(calendar: calendar, event: event)

    expect(adapter).to have_received(:request_json).with(
      hash_including(
        method: :post,
        path: "/calendar/v3/calendars/primary/events",
        body: hash_including(
          "recurrence" => [ "RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=24" ]
        )
      )
    )
    event.reload
    expect(event.remote_event_id).to eq("remote-created-1")
    expect(event.uid).to eq("remote-created-1@google.com")
    expect(event.source_kind).to eq("provider")
  end

  it "does not double-prefix recurrence rules that already include RRULE for Google writes" do
    user, workspace, connection = build_stack(suffix: "write-prefixed-rrule")
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
      title: "Prefixed local provider event",
      starts_at_utc: Time.zone.parse("2026-03-12 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-12 10:00:00"),
      rrule: "RRULE:FREQ=DAILY;COUNT=3",
      source_kind: "local"
    )
    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:request_json).and_return(
      {
        "id" => "remote-created-prefixed",
        "start" => { "dateTime" => "2026-03-12T09:00:00Z" },
        "end" => { "dateTime" => "2026-03-12T10:00:00Z" }
      }
    )

    adapter.upsert_remote_event!(calendar: calendar, event: event)

    expect(adapter).to have_received(:request_json).with(
      hash_including(
        body: hash_including(
          "recurrence" => [ "RRULE:FREQ=DAILY;COUNT=3" ]
        )
      )
    )
  end

  it "updates an existing remote event when remote_event_id is present" do
    user, workspace, connection = build_stack(suffix: "write-update")
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
      title: "Remote existing",
      starts_at_utc: Time.zone.parse("2026-03-13 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-13 10:00:00"),
      source_kind: "provider",
      remote_event_id: "remote-existing-1"
    )
    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:request_json).and_return(
      {
        "id" => "remote-existing-1",
        "status" => "confirmed",
        "start" => { "dateTime" => "2026-03-13T09:00:00Z" },
        "end" => { "dateTime" => "2026-03-13T10:00:00Z" }
      }
    )

    adapter.upsert_remote_event!(calendar: calendar, event: event)

    expect(adapter).to have_received(:request_json).with(
      hash_including(
        method: :patch,
        path: "/calendar/v3/calendars/primary/events/remote-existing-1"
      )
    )
  end

  it "deletes an existing remote event for provider-backed events" do
    user, workspace, connection = build_stack(suffix: "write-delete")
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
      title: "Delete remote",
      starts_at_utc: Time.zone.parse("2026-03-14 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-14 10:00:00"),
      source_kind: "provider",
      remote_event_id: "remote-delete-1"
    )
    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:request_json).and_return({})

    result = adapter.delete_remote_event!(calendar: calendar, event: event)

    expect(result).to be(true)
    expect(adapter).to have_received(:request_json).with(
      hash_including(
        method: :delete,
        path: "/calendar/v3/calendars/primary/events/remote-delete-1"
      )
    )
  end

  it "syncs only the provided calendar when calendar parameter is given" do
    user, workspace, connection = build_stack(suffix: "single-calendar")
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
    untouched_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "work",
      name: "Work",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false
    )
    untouched_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: untouched_calendar,
      title: "Do not touch",
      starts_at_utc: Time.zone.parse("2026-03-10 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-10 10:00:00"),
      source_kind: "provider",
      remote_event_id: "untouched-uid",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    adapter = described_class.new(connection: connection)
    expect(adapter).not_to receive(:fetch_all_remote_calendars)
    allow(adapter).to receive(:fetch_calendar_events) do |calendar_id:, range_start:, range_end:|
      expect(calendar_id).to eq("primary")
      expect(range_start).to be_a(Time)
      expect(range_end).to be_a(Time)
      [
        {
          "id" => "home-only-event",
          "summary" => "Home only",
          "start" => { "dateTime" => "2026-03-10T12:00:00Z" },
          "end" => { "dateTime" => "2026-03-10T13:00:00Z" }
        }
      ]
    end

    adapter.sync!(calendar: calendar)

    expect(calendar.kalendarium_events.find_by(remote_event_id: "home-only-event")).to be_present
    expect(untouched_event.reload.status).to eq("confirmed")
  end

  it "refreshes token and retries when a request is unauthorized" do
    _user, _workspace, connection = build_stack(suffix: "refresh-on-401")
    connection.update!(refresh_token: "refresh-token")
    adapter = described_class.new(connection: connection)
    unauthorized = instance_double(Net::HTTPResponse, code: "401", body: '{"error":{"message":"Invalid Credentials"}}')
    success = instance_double(Net::HTTPResponse, code: "200", body: '{"items":[]}')

    allow(adapter).to receive(:perform_api_get).and_return(unauthorized, success)
    expect(adapter).to receive(:refresh_access_token!).once do
      connection.update!(access_token: "new-access-token")
    end

    payload = adapter.send(:fetch_json, path: "/calendar/v3/users/me/calendarList", params: { maxResults: 1 })

    expect(payload["items"]).to eq([])
  end

  it "raises a clear auth guidance error when unauthorized and refresh is unavailable" do
    _user, _workspace, connection = build_stack(suffix: "unauthorized")
    connection.update_columns(refresh_token: nil)
    adapter = described_class.new(connection: connection)
    unauthorized = instance_double(Net::HTTPResponse, code: "403", body: '{"error":{"message":"Forbidden"}}')

    allow(adapter).to receive(:perform_api_get).and_return(unauthorized)

    expect do
      adapter.send(:fetch_json, path: "/calendar/v3/users/me/calendarList", params: { maxResults: 1 })
    end.to raise_error(RuntimeError, /Google authentication failed \(403\)/)
  end

  it "raises a clear scope guidance error when Google reports insufficient permissions" do
    _user, _workspace, connection = build_stack(suffix: "insufficient-permissions")
    connection.update_columns(refresh_token: nil)
    adapter = described_class.new(connection: connection)
    forbidden = instance_double(Net::HTTPResponse, code: "403", body: '{"error":{"message":"Insufficient permissions"}}')

    allow(adapter).to receive(:perform_api_get).and_return(forbidden)

    expect do
      adapter.send(:fetch_json, path: "/calendar/v3/users/me/calendarList", params: { maxResults: 1 })
    end.to raise_error(RuntimeError, /write permission is missing/)
  end

  it "resolves google oauth client credentials from Rails credentials when env vars are missing" do
    _user, _workspace, connection = build_stack(suffix: "credentials-fallback")
    adapter = described_class.new(connection: connection)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_SECRET").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return(nil)

    credentials = { google: { oauth_client_id: "cred-client-id", oauth_client_secret: "cred-client-secret" } }
    allow(Rails.application).to receive(:credentials).and_return(credentials)

    expect(adapter.send(:google_client_id)).to eq("cred-client-id")
    expect(adapter.send(:google_client_secret)).to eq("cred-client-secret")
  end

  it "prefers global oauth credentials over stale connection-level google client keys" do
    _user, _workspace, connection = build_stack(suffix: "credentials-priority")
    connection.update!(
      settings_json: connection.settings_json.to_h.merge(
        "google_client_id" => "stale-client-id",
        "google_client_secret" => "stale-client-secret"
      )
    )
    adapter = described_class.new(connection: connection)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_SECRET").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return(nil)
    credentials = { google: { oauth_client_id: "fresh-client-id", oauth_client_secret: "fresh-client-secret" } }
    allow(Rails.application).to receive(:credentials).and_return(credentials)

    expect(adapter.send(:google_client_id)).to eq("fresh-client-id")
    expect(adapter.send(:google_client_secret)).to eq("fresh-client-secret")
  end

  it "uses connection-scoped oauth credentials when present" do
    _user, _workspace, connection = build_stack(suffix: "connection-oauth-credentials")
    connection.update!(
      oauth_client_id: "connection-client-id",
      oauth_client_secret: "connection-client-secret"
    )
    adapter = described_class.new(connection: connection)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_ID").and_return("env-client-id")
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_SECRET").and_return("env-client-secret")

    expect(adapter.send(:google_client_id)).to eq("connection-client-id")
    expect(adapter.send(:google_client_secret)).to eq("connection-client-secret")
  end
end
