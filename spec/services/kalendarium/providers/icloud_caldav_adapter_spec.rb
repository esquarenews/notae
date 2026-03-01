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

  it "raises when iCloud credentials are missing" do
    _user, _workspace, connection = build_stack(suffix: "missing-creds")
    connection.update_columns(provider_username: nil, provider_password: nil)

    expect do
      described_class.new(connection: connection).sync!
    end.to raise_error(RuntimeError, "iCloud CalDAV credentials are missing")
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
          time_zone_hint: "Australia/Melbourne"
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
    expect(calendar.read_only).to be(true)
    expect(calendar.source_kind).to eq("provider")
    expect(calendar.metadata_json["ctag"]).to eq("ctag-1")

    imported_event = calendar.kalendarium_events.find_by(remote_event_id: "event-uid-1::2026-03-03T09:00:00.000000Z")
    expect(imported_event).to be_present
    expect(imported_event.title).to eq("Dentist")
    expect(imported_event.location).to eq("Clinic")
    expect(imported_event.status).to eq("confirmed")
    expect(imported_event.visibility).to eq("private")
    expect(imported_event.etag).to eq("\"etag-1\"")
    expect(imported_event.sequence).to eq(3)
    expect(imported_event.source_kind).to eq("provider")

    all_day_event = calendar.kalendarium_events.find_by(remote_event_id: "event-uid-2::2026-03-04T00:00:00.000000Z")
    expect(all_day_event).to be_present
    expect(all_day_event.all_day).to be(true)
    expect(all_day_event.status).to eq("tentative")
    expect(all_day_event.ends_at_utc - all_day_event.starts_at_utc).to eq(1.day)

    expect(stale_event.reload.status).to eq("cancelled")
    expect(stale_calendar.reload.enabled).to be(false)
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
