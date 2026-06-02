require "rails_helper"

RSpec.describe Kalendarium::Providers::IcloudCaldavAdapter do
  def build_stack(suffix:)
    user = User.create!(email: "kal-icloud-adapter-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal iCloud Adapter #{suffix}", slug: "kal-icloud-adapter-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud personal",
      provider_username: "apple-id@example.com",
      provider_password: "app-specific-password"
    )

    [ user, workspace, connection ]
  end

  def http_response(code:, headers: {})
    double("http_response", code: code.to_s, body: "").tap do |response|
      allow(response).to receive(:[]) do |name|
        headers[name]
      end
    end
  end

  it "raises when iCloud credentials are missing" do
    _user, _workspace, connection = build_stack(suffix: "missing-creds")
    connection.update_columns(provider_username: nil, provider_password: nil)

    expect do
      described_class.new(connection: connection).sync!
    end.to raise_error(RuntimeError, "iCloud CalDAV credentials are missing or no longer decryptable. Re-enter the Apple ID email and app-specific password.")
  end

  it "upserts calendars/events and cancels stale provider events" do
    user, workspace, connection = build_stack(suffix: "upsert")
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/home/",
      name: "Old Home",
      color_hex: "#111111",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true,
      enabled: true
    )
    stale_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/old/",
      name: "Old Removed",
      color_hex: "#222222",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true,
      enabled: true
    )
    stale_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Old stale event",
      starts_at_utc: Time.zone.parse("2026-03-05 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-05 11:00:00"),
      source_kind: "provider",
      remote_event_id: "old-uid",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_current_user_principal_href).and_return("/123/principal/")
    allow(adapter).to receive(:fetch_calendar_home_href).with("/123/principal/").and_return("/123/calendars/")
    allow(adapter).to receive(:fetch_remote_calendars).with("/123/calendars/").and_return(
      [
        {
          href: "/123/calendars/home/",
          name: "Home",
          color_hex: "#6F4BFFCC",
          ctag: "ctag-1",
          time_zone_hint: "Australia/Melbourne",
          writable: true
        }
      ]
    )
    allow(adapter).to receive(:fetch_calendar_event_payloads).and_return(
      [
        {
          href: "/123/calendars/home/event-1.ics",
          etag: "\"etag-1\"",
          calendar_data: <<~ICS
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:event-uid-1
            SUMMARY:Dentist
            DESCRIPTION:Routine checkup
            LOCATION:Clinic
            URL:https://meet.google.com/abc-defg-hij
            ATTENDEE;CN=Alex;PARTSTAT=ACCEPTED:mailto:alex@example.com
            ATTENDEE;PARTSTAT=NEEDS-ACTION:mailto:sam@example.com
            DTSTART:20260303T090000Z
            DTEND:20260303T100000Z
            STATUS:CONFIRMED
            CLASS:PRIVATE
            SEQUENCE:3
            END:VEVENT
            BEGIN:VEVENT
            UID:event-uid-2
            SUMMARY:Public holiday
            DTSTART;VALUE=DATE:20260304
            STATUS:TENTATIVE
            END:VEVENT
            END:VCALENDAR
          ICS
        }
      ]
    )

    adapter.sync!

    calendar.reload
    expect(calendar.name).to eq("Home")
    expect(calendar.color_hex).to eq("#6F4BFF")
    expect(calendar.time_zone).to eq("Australia/Melbourne")
    expect(calendar.read_only).to be(false)
    expect(calendar.user_writable?).to be(true)
    expect(calendar.source_kind).to eq("provider")
    expect(calendar.metadata_json["ctag"]).to eq("ctag-1")
    expect(calendar.metadata_json["writable"]).to be(true)

    imported_event = calendar.kalendarium_events.find_by(remote_event_id: "event-uid-1::2026-03-03T09:00:00.000000Z")
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
      { "email" => "sam@example.com", "status" => "needs-action" }
    )

    all_day_event = calendar.kalendarium_events.find_by(remote_event_id: "event-uid-2::2026-03-04T00:00:00.000000Z")
    expect(all_day_event).to be_present
    expect(all_day_event.all_day).to be(true)
    expect(all_day_event.status).to eq("tentative")
    expect(all_day_event.ends_at_utc - all_day_event.starts_at_utc).to eq(1.day)

    expect(stale_event.reload.status).to eq("cancelled")
    expect(stale_calendar.reload.enabled).to be(false)
  end

  it "fails sync when iCloud returns no calendars and preserves existing data" do
    user, workspace, connection = build_stack(suffix: "empty-calendars")
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
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Keep me",
      starts_at_utc: Time.zone.parse("2026-03-05 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-05 11:00:00"),
      source_kind: "provider",
      remote_event_id: "keep-uid",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_current_user_principal_href).and_return("/123/principal/")
    allow(adapter).to receive(:fetch_calendar_home_href).with("/123/principal/").and_return("/123/calendars/")
    allow(adapter).to receive(:fetch_remote_calendars).with("/123/calendars/").and_return([])

    expect do
      adapter.sync!
    end.to raise_error(RuntimeError, /No calendars were returned from iCloud CalDAV/)

    expect(calendar.reload.enabled).to be(true)
    expect(event.reload.status).to eq("confirmed")
  end

  it "preserves a locally moved provider event when the original iCloud calendar syncs again" do
    user, workspace, connection = build_stack(suffix: "preserve-moved-event")
    source_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/source/",
      name: "Source",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    target_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/target/",
      name: "Target",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    moved_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: target_calendar,
      created_by: user,
      updated_by: user,
      title: "Moved locally",
      starts_at_utc: Time.zone.parse("2026-03-03 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-03 10:00:00"),
      source_kind: "provider",
      remote_event_id: "event-uid-1::2026-03-03T09:00:00.000000Z"
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_calendar_event_payloads).and_return(
      [
        {
          href: "/123/calendars/source/event-uid-1.ics",
          etag: "\"etag-1\"",
          calendar_data: <<~ICS
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:event-uid-1
            SUMMARY:Remote still on source
            DTSTART:20260303T090000Z
            DTEND:20260303T100000Z
            STATUS:CONFIRMED
            END:VEVENT
            END:VCALENDAR
          ICS
        }
      ]
    )

    adapter.sync!(calendar: source_calendar)

    expect(KalendariumEvent.where(remote_event_id: "event-uid-1::2026-03-03T09:00:00.000000Z").count).to eq(1)
    expect(moved_event.reload.kalendarium_calendar_id).to eq(target_calendar.id)
    expect(moved_event.title).to eq("Remote still on source")
  end

  it "fails sync when calendar parsing returns no events for a populated provider calendar" do
    user, workspace, connection = build_stack(suffix: "empty-events")
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
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Keep me too",
      starts_at_utc: Time.zone.parse("2026-03-08 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-08 10:00:00"),
      source_kind: "provider",
      remote_event_id: "keep-event-uid",
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_calendar_event_payloads).and_return(
      [
        {
          href: "/123/calendars/home/event-empty.ics",
          etag: "\"etag-empty\"",
          calendar_data: <<~ICS
            BEGIN:VCALENDAR
            PRODID:-//Example//No Events//EN
            END:VCALENDAR
          ICS
        }
      ]
    )

    expect { adapter.sync!(calendar: calendar) }.not_to raise_error
    expect(event.reload.status).to eq("confirmed")
  end

  it "re-enables calendars that were auto-disabled after a missing-calendar sync" do
    user, workspace, connection = build_stack(suffix: "re-enable-auto-disabled")
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
      enabled: false,
      metadata_json: { "auto_disabled_missing" => true, "auto_disabled_missing_at" => Time.current.iso8601 }
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_current_user_principal_href).and_return("/123/principal/")
    allow(adapter).to receive(:fetch_calendar_home_href).with("/123/principal/").and_return("/123/calendars/")
    allow(adapter).to receive(:fetch_remote_calendars).with("/123/calendars/").and_return(
      [
        {
          href: "/123/calendars/home/",
          name: "Home",
          color_hex: "#3B82F6",
          ctag: "ctag-home",
          time_zone_hint: "UTC",
          writable: true
        }
      ]
    )
    allow(adapter).to receive(:fetch_calendar_event_payloads).and_return([])

    adapter.sync!

    expect(calendar.reload.enabled).to be(true)
    expect(calendar.read_only).to be(false)
    expect(calendar.metadata_json["auto_disabled_missing"]).to be_nil
    expect(calendar.metadata_json["auto_disabled_missing_at"]).to be_nil
  end

  it "creates a new remote event for writable iCloud calendars and updates the local event" do
    user, workspace, connection = build_stack(suffix: "write-create")
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
      metadata_json: { "subscribed" => false }
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Local provider event",
      description: "Write this remotely",
      starts_at_utc: Time.zone.parse("2026-03-12 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-12 10:00:00"),
      rrule: "FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=24",
      source_kind: "local"
    )

    adapter = described_class.new(connection: connection)
    captured = nil
    allow(adapter).to receive(:perform_caldav_write_request) do |**args|
      captured = args
      http_response(code: 201, headers: { "ETag" => "\"etag-created\"" })
    end

    adapter.upsert_remote_event!(calendar: calendar, event: event)

    expect(captured[:method]).to eq("PUT")
    expect(captured[:href]).to start_with("/123/calendars/home/")
    expect(captured[:body]).to include("BEGIN:VEVENT")
    expect(captured[:body]).to include("UID:#{event.id}@notae.local")
    expect(captured[:body]).to include("SUMMARY:Local provider event")
    expect(captured[:body]).to include("DESCRIPTION:Write this remotely")
    expect(captured[:body]).to include("RRULE:FREQ=WEEKLY;INTERVAL=1;BYDAY=MO,WE;COUNT=24")
    expect(captured[:headers]).to eq({})

    event.reload
    expect(event.remote_event_id).to eq("#{event.id}@notae.local::#{event.starts_at_utc.utc.iso8601(6)}")
    expect(event.uid).to eq("#{event.id}@notae.local")
    expect(event.etag).to eq("\"etag-created\"")
    expect(event.sequence).to eq(0)
    expect(event.source_kind).to eq("provider")
    expect(event.metadata_json["remote_href"]).to eq(captured[:href])
  end

  it "updates an existing remote event for writable iCloud calendars" do
    user, workspace, connection = build_stack(suffix: "write-update")
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
      read_only: false,
      metadata_json: { "subscribed" => false, "writable" => true }
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Remote existing",
      starts_at_utc: Time.zone.parse("2026-03-13 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-13 10:00:00"),
      rrule: "RRULE:FREQ=DAILY;COUNT=3",
      source_kind: "provider",
      remote_event_id: "legacy-remote-id",
      uid: "remote-existing-uid",
      etag: "\"etag-old\"",
      sequence: 3,
      metadata_json: { "remote_href" => "/123/calendars/home/existing.ics" }
    )

    adapter = described_class.new(connection: connection)
    captured = nil
    allow(adapter).to receive(:perform_caldav_write_request) do |**args|
      captured = args
      http_response(code: 204, headers: { "ETag" => "\"etag-updated\"" })
    end

    adapter.upsert_remote_event!(calendar: calendar, event: event)

    expect(captured[:method]).to eq("PUT")
    expect(captured[:href]).to eq("/123/calendars/home/existing.ics")
    expect(captured[:headers]).to eq({ "If-Match" => "\"etag-old\"" })
    expect(captured[:body]).to include("UID:remote-existing-uid")
    expect(captured[:body]).to include("SEQUENCE:4")
    expect(captured[:body]).to include("RRULE:FREQ=DAILY;COUNT=3")
    expect(captured[:body]).not_to include("RRULE:RRULE")

    event.reload
    expect(event.remote_event_id).to eq("remote-existing-uid::#{event.starts_at_utc.utc.iso8601(6)}")
    expect(event.etag).to eq("\"etag-updated\"")
    expect(event.sequence).to eq(4)
    expect(event.metadata_json["remote_href"]).to eq("/123/calendars/home/existing.ics")
  end

  it "moves an existing iCloud event by writing it to the target calendar and deleting the source href" do
    user, workspace, connection = build_stack(suffix: "write-move")
    source_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/source/",
      name: "Source",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false
    )
    target_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/target/",
      name: "Target",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: target_calendar,
      created_by: user,
      updated_by: user,
      title: "Moved iCloud",
      starts_at_utc: Time.zone.parse("2026-03-13 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-13 10:00:00"),
      source_kind: "provider",
      remote_event_id: "/123/calendars/source/old-event.ics::2026-03-13T09:00:00.000000Z",
      uid: "old-event",
      etag: "\"old-etag\"",
      metadata_json: {
        "pending_provider_calendar_move" => true,
        "previous_calendar_id" => source_calendar.id,
        "previous_remote_event_id" => "/123/calendars/source/old-event.ics::2026-03-13T09:00:00.000000Z",
        "previous_remote_href" => "/123/calendars/source/old-event.ics",
        "previous_remote_etag" => "\"old-etag\"",
        "remote_href" => "/123/calendars/source/old-event.ics"
      }
    )

    adapter = described_class.new(connection: connection)
    calls = []
    allow(adapter).to receive(:perform_caldav_write_request) do |**args|
      calls << args
      case [ args[:method], args[:href] ]
      when [ "PUT", "/123/calendars/target/old-event-7e0a12ff943f.ics" ]
        http_response(code: 201, headers: { "Location" => "/123/calendars/target/new-event.ics", "ETag" => "\"new-etag\"" })
      when [ "DELETE", "/123/calendars/source/old-event.ics" ]
        http_response(code: 204)
      else
        raise "Unexpected #{args[:method]} #{args[:href]}"
      end
    end

    adapter.move_remote_event!(from_calendar: source_calendar, to_calendar: target_calendar, event: event)

    expect(calls).to include(hash_including(method: "PUT", href: "/123/calendars/target/old-event-7e0a12ff943f.ics"))
    expect(calls).to include(hash_including(method: "DELETE", href: "/123/calendars/source/old-event.ics", headers: { "If-Match" => "\"old-etag\"" }))
    expect(event.reload.metadata_json["remote_href"]).to eq("/123/calendars/target/new-event.ics")
  end

  it "deletes an existing remote event for writable iCloud calendars" do
    user, workspace, connection = build_stack(suffix: "write-delete")
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
      read_only: false,
      metadata_json: { "subscribed" => false, "writable" => true }
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
      remote_event_id: "remote-delete-1",
      uid: "remote-delete-uid",
      etag: "\"etag-delete\"",
      metadata_json: { "remote_href" => "/123/calendars/home/delete.ics" }
    )

    adapter = described_class.new(connection: connection)
    captured = nil
    allow(adapter).to receive(:perform_caldav_write_request) do |**args|
      captured = args
      http_response(code: 204)
    end

    result = adapter.delete_remote_event!(calendar: calendar, event: event)

    expect(result).to be(true)
    expect(captured[:method]).to eq("DELETE")
    expect(captured[:href]).to eq("/123/calendars/home/delete.ics")
    expect(captured[:headers]).to eq({ "If-Match" => "\"etag-delete\"" })
  end

  it "syncs only the provided calendar when calendar parameter is given" do
    user, workspace, connection = build_stack(suffix: "single-calendar")
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
      read_only: true
    )
    untouched_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/work/",
      name: "Work",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true
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
    expect(adapter).not_to receive(:fetch_current_user_principal_href)
    allow(adapter).to receive(:fetch_calendar_event_payloads) do |href, range_start:, range_end:|
      expect(href).to eq("/123/calendars/home/")
      expect(range_start).to be_a(Time)
      expect(range_end).to be_a(Time)
      [
        {
          href: "/123/calendars/home/event-2.ics",
          etag: "\"etag-2\"",
          calendar_data: <<~ICS
            BEGIN:VCALENDAR
            BEGIN:VEVENT
            UID:event-uid-home-only
            SUMMARY:Home only
            DTSTART:20260310T120000Z
            DTEND:20260310T130000Z
            END:VEVENT
            END:VCALENDAR
          ICS
        }
      ]
    end

    adapter.sync!(calendar: calendar)

    expect(calendar.kalendarium_events.find_by(remote_event_id: "event-uid-home-only::2026-03-10T12:00:00.000000Z")).to be_present
    expect(untouched_event.reload.status).to eq("confirmed")
  end

  it "creates separate events for expanded recurrences sharing the same uid" do
    user, workspace, connection = build_stack(suffix: "expanded-uid")
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/home/",
      name: "Home",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "provider",
      read_only: true
    )

    adapter = described_class.new(connection: connection)
    allow(adapter).to receive(:fetch_calendar_event_payloads).and_return(
      [
        {
          href: "/123/calendars/home/series.ics",
          etag: "\"etag-series\"",
          calendar_data: <<~ICS
            BEGIN:VCALENDAR
            X-EXPANDED:True
            BEGIN:VEVENT
            UID:series-uid-1
            SUMMARY:Dance class
            DTSTART;TZID=Australia/Melbourne:20260303T163000
            DTEND;TZID=Australia/Melbourne:20260303T174500
            END:VEVENT
            BEGIN:VEVENT
            UID:series-uid-1
            SUMMARY:Dance class
            DTSTART;TZID=Australia/Melbourne:20260310T163000
            DTEND;TZID=Australia/Melbourne:20260310T174500
            END:VEVENT
            END:VCALENDAR
          ICS
        }
      ]
    )

    adapter.sync!(calendar: calendar)

    imported_ids = calendar.kalendarium_events.order(:starts_at_utc).pluck(:remote_event_id)
    expect(imported_ids).to include("series-uid-1::2026-03-03T05:30:00.000000Z")
    expect(imported_ids).to include("series-uid-1::2026-03-10T05:30:00.000000Z")
  end

  it "raises a credential guidance error on CalDAV 401 responses" do
    _user, _workspace, connection = build_stack(suffix: "auth-401")
    adapter = described_class.new(connection: connection)
    unauthorized_response = instance_double(Net::HTTPResponse, code: "401", body: "", :[] => nil)

    allow(adapter).to receive(:perform_request).and_return(unauthorized_response)

    expect do
      adapter.send(:perform_xml_request, method: "PROPFIND", href: "/", body: "<x/>", depth: "0")
    end.to raise_error(RuntimeError, /CalDAV authentication failed \(401\)/)
  end

  it "ignores connection ics_url overrides and always targets iCloud CalDAV host" do
    _user, _workspace, connection = build_stack(suffix: "fixed-host")
    connection.update!(ics_url: "https://idmsa.apple.com")

    adapter = described_class.new(connection: connection)
    uri = adapter.send(:caldav_base_uri)

    expect(uri.host).to eq("caldav.icloud.com")
  end

  it "recognizes subscribed calendars as remote calendars to import" do
    _user, _workspace, connection = build_stack(suffix: "subscribed")
    adapter = described_class.new(connection: connection)
    prop = REXML::Document.new(<<~XML).root
      <d:prop xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
        <d:resourcetype>
          <d:collection />
          <cs:subscribed />
        </d:resourcetype>
      </d:prop>
    XML

    type = adapter.send(:calendar_resource_type, prop)

    expect(type[:calendar]).to be(false)
    expect(type[:subscribed]).to be(true)
  end

  it "requests expanded vevent data in calendar queries" do
    _user, _workspace, connection = build_stack(suffix: "expand-query")
    adapter = described_class.new(connection: connection)
    captured = nil

    allow(adapter).to receive(:report) do |href, body:, depth:|
      captured = { href: href, body: body, depth: depth }
      []
    end

    adapter.send(
      :fetch_calendar_event_payloads,
      "/123/calendars/home/",
      range_start: Time.utc(2026, 3, 1, 0, 0, 0),
      range_end: Time.utc(2026, 3, 2, 0, 0, 0)
    )

    expect(captured[:href]).to eq("/123/calendars/home/")
    expect(captured[:depth]).to eq("1")
    expect(captured[:body]).to include("<c:expand")
    expect(captured[:body]).to include("<c:prop name=\"DTSTART\"")
    expect(captured[:body]).to include("<c:prop name=\"RRULE\"")
  end
end
