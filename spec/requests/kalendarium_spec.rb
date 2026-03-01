require "rails_helper"

RSpec.describe "Kalendarium", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def build_stack(suffix:)
    user = User.create!(email: "kal-request-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Request #{suffix}", slug: "kal-request-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    [ user, workspace, calendar ]
  end

  it "renders the kalendarium page and shows the sidebar entry" do
    user, workspace, = build_stack(suffix: "show")
    sign_in user

    get kalendarium_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Kalendārium")
    expect(response.body).to include("Day")
    expect(response.body).to include("Week")
    expect(response.body).to include("Month")
    expect(response.body).to include("Year")
    expect(response.body).to include("Project")
    expect(response.body).to include("data-controller=\"kalendarium-focus\"")
    expect(response.body).to include("notae-kalendarium-sidebar-accordion-summary")
  end

  it "renders day and week timelines with hourly rails and half-hour markers" do
    user, workspace, calendar = build_stack(suffix: "timeline")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Timeline event",
      starts_at_utc: Time.zone.parse("2026-03-01 09:30:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:30:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h2>Sunday, 1 March 2026</h2>")
    expect(response.body).to include("data-kalendarium-timeline-start-hour-value=\"5\"")
    expect(response.body).to include("05:00")
    expect(response.body).to include("20:00")
    expect(response.body).to include("notae-kalendarium-time-half")
    expect(response.body).to include("notae-kalendarium-now-line")
    expect(response.body).to include("data-kalendarium-timeline-time-zone-value=")
    expect(response.body).to include("aria-label=\"Edit event\"")
    expect(response.body).to include("kalendarium-event-modal#openView")
    expect(response.body).to include("Event details")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-week-header-days")
    expect(response.body).to include("notae-kalendarium-week-columns")
    expect(response.body).to include("notae-kalendarium-week-day-label")
    expect(response.body).to include("notae-kalendarium-timeline-scroller-week")
    expect(response.body).to include("data-now-date=\"2026-03-01\"")
    expect(response.body).to include("data-kalendarium-day-focus=\"true\"")
    expect(response.body).to include("data-day-date=\"2026-03-01\"")
    expect(response.body).to include("click-&gt;kalendarium-focus#selectDay")
    expect(response.body).to include("data-kalendarium-focus-target=\"viewLink\"")
    expect(response.body).to include("data-kalendarium-focus-target=\"weekTrack\"")
    expect(response.body).to include("notae-kalendarium-day-focus-link is-selected")
    expect(response.body).to include("notae-kalendarium-week-day-track is-selected")
    expect(response.body).to include("date=2026-03-01&amp;view=day")

    travel_to Time.zone.parse("2026-03-15 09:30:00") do
      get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-01")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Month view · March 2026")
      expect(response.body).to include("data-kalendarium-day-focus=\"true\"")
      expect(response.body).to include("data-day-date=\"2026-03-15\"")
      expect(response.body).to include("notae-kalendarium-month-cell is-today")
      expect(response.body).to include("notae-kalendarium-month-cell is-selected")
      expect(response.body).to include("notae-kalendarium-month-day-focus-link is-today")
      expect(response.body).to include("notae-kalendarium-month-day-focus-link is-selected")
      expect(response.body).to include("date=2026-03-01&amp;view=day")

      get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<h2>2026</h2>")
      expect(response.body).to include("data-day-date=\"2026-03-15\"")
      expect(response.body).to include("notae-kalendarium-year-day is-today")
      expect(response.body).to include("notae-kalendarium-year-day is-selected")
    end
  end

  it "keeps the selected date when switching to day view from month and week" do
    user, workspace, = build_stack(suffix: "selected-date-switch")
    sign_in user

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-15")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-month-cell is-selected")
    expect(response.body).to include("notae-kalendarium-month-day-focus-link is-selected")
    expect(response.body).to include("date=2026-03-15&amp;view=day")

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-15")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h2>Sunday, 15 March 2026</h2>")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-18")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-day-focus-link is-selected")
    expect(response.body).to include("notae-kalendarium-week-day-track is-selected")
    expect(response.body).to include("date=2026-03-18&amp;view=day")
  end

  it "renders equal start/end timeline events using a minimum slot height" do
    user, workspace, calendar = build_stack(suffix: "equal-time-timeline")
    user.update!(time_zone: "UTC")
    sign_in user

    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Equal time event",
      starts_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 12:00:00")
    )
    event.update_column(:ends_at_utc, event.starts_at_utc)

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")
    expect(response).to have_http_status(:ok)

    day_doc = Nokogiri::HTML.parse(response.body)
    day_card = day_doc.at_css("#kalendarium_event_#{event.id}")
    expect(day_card).to be_present
    expect(day_card["style"]).to include("height: 28.0px;")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-01")
    expect(response).to have_http_status(:ok)

    week_doc = Nokogiri::HTML.parse(response.body)
    week_card = week_doc.at_css("#kalendarium_event_#{event.id}")
    expect(week_card).to be_present
    expect(week_card["style"]).to include("height: 28.0px;")
  end

  it "renders separate calendar and project dropdown filters that preserve each other state" do
    user, workspace, calendar = build_stack(suffix: "separate-filters")
    sign_in user

    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Client Work",
      color_hex: "#8B5CF6"
    )

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "month",
      date: "2026-03-01",
      calendar_ids: [ calendar.id ],
      project_id: project.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendars (1)")
    expect(response.body).to include("Projects (Client Work)")
    expect(response.body).to include("class=\"notae-kalendarium-calendar-filter\"")
    expect(response.body).to include("class=\"notae-kalendarium-project-filter\"")
    expect(response.body).to include("data-controller=\"floating-panel\"")
    expect(response.body).to include("data-floating-panel-target=\"summary\"")
    expect(response.body).to include("data-floating-panel-target=\"panel\"")
    expect(response.body).to include("name=\"calendar_ids[]\"")
    expect(response.body).to include("name=\"project_id\"")
    expect(response.body).to include("All projects")
  end

  it "respects monday week-start preference for week, month, and year views" do
    user, workspace, = build_stack(suffix: "week-start-monday")
    user.update!(start_week_on_monday: true)
    sign_in user

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-day-date=\"2026-02-23\"")

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-month-weekday\">Mon</div>")
    expect(response.body).to include("notae-kalendarium-month-weekday\">Sun</div>")
    expect(response.body).to include("data-day-date=\"2026-02-23\"")
    expect(response.body).not_to include("data-day-date=\"2026-02-22\"")

    get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-year-weekday\">M</span>")
    expect(response.body).to include("data-day-date=\"2025-12-29\"")
    expect(response.body).not_to include("data-day-date=\"2025-12-28\"")
  end

  it "creates a project and auto-creates a matching calendar" do
    user, workspace, = build_stack(suffix: "project-create")
    sign_in user

    expect do
      post kalendarium_projects_path(workspace_slug: workspace.slug), params: {
        kalendarium_project: {
          name: "Launch",
          slug: "launch",
          color_hex: "#8B5CF6"
        }
      }
    end.to change(KalendariumProject, :count).by(1).and change(KalendariumCalendar, :count).by(1)

    project = KalendariumProject.order(:created_at).last
    expect(project.kalendarium_calendar).to be_present
    expect(project.kalendarium_calendar.name).to eq("Launch")
    expect(project.kalendarium_calendar.color_hex).to eq("#8B5CF6")
  end

  it "creates events with optional quick Nota links and rejects invalid times" do
    user, workspace, calendar = build_stack(suffix: "event-create")
    sign_in user

    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      kalendarium_event: {
        kalendarium_calendar_id: calendar.id,
        title: "Planning",
        starts_at_local: "2026-03-01T10:00",
        ends_at_local: "2026-03-01T11:00",
        linked_page_action: "create_page",
        reminder_offsets_minutes: %w[10 30]
      }
    }

    created_event = KalendariumEvent.order(:created_at).last
    expect(created_event.title).to eq("Planning")
    expect(created_event.linked_page).to be_present
    expect(created_event.reminder_offsets_minutes).to eq([ 10, 30 ])

    expect do
      post kalendarium_events_path(workspace_slug: workspace.slug), params: {
        kalendarium_event: {
          kalendarium_calendar_id: calendar.id,
          title: "Broken",
          starts_at_local: "not-a-date",
          ends_at_local: "also-not-a-date"
        }
      }
    end.not_to change(KalendariumEvent, :count)

    expect(flash[:alert]).to include("must be valid")
  end

  it "updates and deletes events via kalendarium event endpoints" do
    user, workspace, calendar = build_stack(suffix: "event-edit-delete")
    sign_in user

    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Draft event",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )

    patch kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: {
      view: "day",
      date: "2026-03-01",
      kalendarium_event: {
        title: "Final event",
        starts_at_local: "2026-03-01T09:30",
        ends_at_local: "2026-03-01T10:30"
      }
    }

    expect(response).to redirect_to(kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01"))
    expect(event.reload.title).to eq("Final event")

    expect do
      delete kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: { view: "day", date: "2026-03-01" }
    end.to change(KalendariumEvent, :count).by(-1)
  end

  it "does not render cancelled events in calendar views" do
    user, workspace, calendar = build_stack(suffix: "cancelled-filter")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Visible event",
      status: "confirmed",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Cancelled event",
      status: "cancelled",
      starts_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 12:00:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible event")
    expect(response.body).not_to include("Cancelled event")
  end
end
