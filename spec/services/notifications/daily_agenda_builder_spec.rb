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
