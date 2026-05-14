require "rails_helper"

RSpec.describe Notifications::DailyAgendaBuilder do
  it "builds a clean agenda for the user's local day and excludes cancelled events" do
    user = User.create!(email: "daily-agenda@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Daily agenda", slug: "daily-agenda")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Primary",
      color_hex: "#2563eb",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )
    melbourne = ActiveSupport::TimeZone["Australia/Melbourne"]

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Company offsite",
      all_day: true,
      starts_at_utc: melbourne.parse("2026-04-17 00:00").utc,
      ends_at_utc: melbourne.parse("2026-04-17 23:59").utc
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Stand-up",
      starts_at_utc: melbourne.parse("2026-04-17 09:00").utc,
      ends_at_utc: melbourne.parse("2026-04-17 09:30").utc
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Client review",
      starts_at_utc: melbourne.parse("2026-04-17 14:30").utc,
      ends_at_utc: melbourne.parse("2026-04-17 15:00").utc
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Cancelled catch-up",
      status: "cancelled",
      starts_at_utc: melbourne.parse("2026-04-17 11:00").utc,
      ends_at_utc: melbourne.parse("2026-04-17 11:30").utc
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Tomorrow item",
      starts_at_utc: melbourne.parse("2026-04-18 09:00").utc,
      ends_at_utc: melbourne.parse("2026-04-18 09:30").utc
    )

    payload = described_class.new(
      user: user,
      workspace: workspace,
      date: Date.new(2026, 4, 17)
    ).call

    expect(payload).to include(
      "daily_agenda_date" => "2026-04-17",
      "daily_agenda_total_count" => 3,
      "daily_agenda_empty" => false
    )
    expect(payload.fetch("daily_agenda_items")).to match(
      [
        a_hash_including("time" => "All day", "title" => "Company offsite", "all_day" => true),
        a_hash_including("time" => "09:00", "title" => "Stand-up", "all_day" => false),
        a_hash_including("time" => "14:30", "title" => "Client review", "all_day" => false)
      ]
    )
  end
end

RSpec.describe Notifications::DailyAgendaBuilder do
  it "only includes shared calendars and the recipient's personal calendars" do
    owner = User.create!(email: "calendar-owner@example.com", password: "password123", time_zone: "UTC")
    recipient = User.create!(email: "calendar-recipient@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Agenda privacy", slug: "agenda-privacy")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: recipient, role: :member)

    shared_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: owner,
      provider: "ics",
      label: "Workspace",
      ics_url: "https://example.com/shared.ics"
    )
    shared_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: shared_connection,
      created_by: owner,
      name: "Shared",
      color_hex: "#2563eb",
      time_zone: "UTC",
      source_kind: "provider"
    )

    recipient_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: recipient,
      created_by: recipient,
      provider: "ics",
      label: "Recipient personal",
      ics_url: "https://example.com/recipient.ics"
    )
    recipient_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: recipient_connection,
      created_by: recipient,
      name: "Recipient",
      color_hex: "#16a34a",
      time_zone: "UTC",
      source_kind: "provider"
    )

    owner_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "ics",
      label: "Owner personal",
      ics_url: "https://example.com/owner.ics"
    )
    owner_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: owner_connection,
      created_by: owner,
      name: "Owner",
      color_hex: "#dc2626",
      time_zone: "UTC",
      source_kind: "provider"
    )

    date = Date.new(2026, 4, 17)
    [ [ shared_calendar, "Shared planning", owner ], [ recipient_calendar, "My private task", recipient ], [ owner_calendar, "Owner private task", owner ] ].each do |calendar, title, actor|
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: calendar,
        created_by: actor,
        updated_by: actor,
        title: title,
        starts_at_utc: Time.utc(2026, 4, 17, 10, 0),
        ends_at_utc: Time.utc(2026, 4, 17, 10, 30)
      )
    end

    payload = described_class.new(user: recipient, workspace: workspace, date: date).call

    expect(payload.fetch("daily_agenda_items").map { |item| item.fetch("title") }).to contain_exactly(
      "Shared planning",
      "My private task"
    )
    expect(payload.fetch("daily_agenda_total_count")).to eq(2)
  end
end
