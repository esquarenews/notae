require "rails_helper"

RSpec.describe KalendariumCalendarPolicy::Scope do
  before do
    allow(Search::IndexKalendariumEventJob).to receive(:perform_later)
  end

  it "returns local and shared-connection calendars but not another user's personal calendars" do
    workspace = Workspace.create!(name: "Calendar scope", slug: "calendar-scope")
    owner = User.create!(email: "calendar-scope-owner@example.com", password: "password123")
    member = User.create!(email: "calendar-scope-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    shared_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: workspace,
      created_by: owner,
      provider: "ics",
      label: "Shared feed",
      ics_url: "https://example.com/shared.ics"
    )
    owner_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "google",
      label: "Owner personal",
      access_token: "owner-token"
    )
    local_calendar = create_calendar(workspace: workspace, created_by: owner, name: "Local")
    shared_calendar = create_calendar(workspace: workspace, created_by: owner, name: "Shared", connection: shared_connection)
    hidden_calendar = create_calendar(workspace: workspace, created_by: owner, name: "Hidden", connection: owner_connection)

    scoped_ids = described_class.new(member, KalendariumCalendar).resolve.pluck(:id)

    expect(scoped_ids).to contain_exactly(local_calendar.id, shared_calendar.id)
    expect(scoped_ids).not_to include(hidden_calendar.id)
  end

  def create_calendar(workspace:, created_by:, name:, connection: nil)
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: created_by,
      kalendarium_connection: connection,
      name: name,
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: connection.present? ? "provider" : "local"
    )
  end
end

RSpec.describe KalendariumEventPolicy::Scope do
  before do
    allow(Search::IndexKalendariumEventJob).to receive(:perform_later)
  end

  it "returns only events from calendars visible to the user" do
    workspace = Workspace.create!(name: "Event scope", slug: "event-scope")
    owner = User.create!(email: "event-scope-owner@example.com", password: "password123")
    member = User.create!(email: "event-scope-member@example.com", password: "password123")

    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)

    owner_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "google",
      label: "Owner personal",
      access_token: "owner-token"
    )
    visible_calendar = create_calendar(workspace: workspace, created_by: owner, name: "Visible")
    hidden_calendar = create_calendar(workspace: workspace, created_by: owner, name: "Hidden", connection: owner_connection)
    visible_event = create_event(workspace: workspace, calendar: visible_calendar, user: owner, title: "Visible event")
    hidden_event = create_event(workspace: workspace, calendar: hidden_calendar, user: owner, title: "Hidden event")

    resolved_scope = described_class.new(member, KalendariumEvent).resolve

    expect(resolved_scope).to include(visible_event)
    expect(resolved_scope).not_to include(hidden_event)
  end

  def create_calendar(workspace:, created_by:, name:, connection: nil)
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: created_by,
      kalendarium_connection: connection,
      name: name,
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: connection.present? ? "provider" : "local"
    )
  end

  def create_event(workspace:, calendar:, user:, title:)
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: title,
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
  end
end
