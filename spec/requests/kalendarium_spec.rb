require "rails_helper"

RSpec.describe "Kalendarium", type: :request do
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
    expect(response.body).to include("data-kalendarium-timeline-start-hour-value=\"5\"")
    expect(response.body).to include("05:00")
    expect(response.body).to include("20:00")
    expect(response.body).to include("notae-kalendarium-time-half")
    expect(response.body).to include("aria-label=\"Edit event\"")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-week-header-days")
    expect(response.body).to include("notae-kalendarium-week-columns")
    expect(response.body).to include("notae-kalendarium-week-day-label")
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
end
