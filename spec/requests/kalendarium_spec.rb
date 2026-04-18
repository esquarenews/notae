require "rails_helper"

RSpec.describe "Kalendarium", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    clear_enqueued_jobs
  end

  def build_stack(suffix:, theme_preference: nil, time_zone: nil)
    user_attributes = {
      email: "kal-request-#{suffix}@example.com",
      password: "password123"
    }
    user_attributes[:theme_preference] = theme_preference if theme_preference.present?
    user_attributes[:time_zone] = time_zone if time_zone.present?
    user = User.create!(**user_attributes)
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
    expect(response.body).to include("Next 7 days")
    expect(response.body).to include("Week")
    expect(response.body).to include("Month")
    expect(response.body).to include("Year")
    expect(response.body).to include("Project")
    expect(response.body).to include("data-controller=\"kalendarium-focus kalendarium-preview\"")
    expect(response.body).to include("notae-kalendarium-sidebar-accordion-summary")
    expect(response.body).to include("name=\"kalendarium_workspace\"")
    expect(response.body).to include("aria-label=\"Refresh calendars\"")
    expect(response.body).to include("notae-kalendarium-week-header-days")
    expect(response.body).to include("name=\"kalendarium_event[all_day]\"")
    expect(response.body).to include("notae-content-kalendarium")
    expect(response.body).to include("notae-tool-page-title")
    expect(response.body).to include("notae-topbar-page-icon-glyph")
    expect(response.body).not_to include(">10m</span>")
    expect(response.headers["X-Notae-Perf-Action"]).to eq("KalendariumController#show")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present
    document = Nokogiri::HTML.parse(response.body)
    content = document.at_css("main.notae-content")
    kalendarium_shell = document.at_css(".notae-kalendarium")
    expect(content&.[]("class")).to include("notae-content-wide")
    expect(content&.[]("class")).to include("notae-content-kalendarium")
    expect(content&.[]("class")).not_to include("notae-content-overlay-page")
    expect(kalendarium_shell).to be_present
    expect(kalendarium_shell["data-action"]).to include("kalendarium:quick-create->kalendarium-focus#prepareNewEvent")
    expect(kalendarium_shell["data-action"]).to include("kalendarium:preview-event->kalendarium-preview#render")
    expect(kalendarium_shell["data-action"]).to include("kalendarium:preview-clear->kalendarium-preview#clear")
    sticky_sidebar = document.at_css("aside.notae-kalendarium-sidebar.is-pinned")
    expect(sticky_sidebar).to be_present
    expect(sticky_sidebar.at_css(".notae-kalendarium-sidebar-accordion-summary")&.text.to_s.strip).to eq("Create event")
    expect(sticky_sidebar.at_css("[data-kalendarium-focus-target='createAccordion']")).to be_present
    create_form = sticky_sidebar.at_css("form[data-controller='kalendarium-event-form']")
    expect(create_form).to be_present
    expect(create_form["data-kalendarium-event-form-preview-enabled-value"]).to eq("true")
    expect(create_form.at_css("[data-kalendarium-event-form-target='titleInput']")).to be_present
    expect(create_form.at_css("button[data-action='kalendarium-event-form#cancel']")&.text.to_s.strip).to eq("Cancel")
    active_view_link = document.css("a.notae-chip-button.is-active").find { |link| link.text.strip == "Week" }
    expect(active_view_link).to be_present
  end

  it "renders embedded task slot suggestions and hides the create event accordion" do
    user, workspace, calendar = build_stack(suffix: "task-slots", time_zone: "UTC")
    database = Database.create!(workspace: workspace, created_by: user, name: "Task Grid")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review roadmap")
    tasks_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Tasks",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "project"
    )
    tasks_project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: tasks_calendar,
      name: "Tasks",
      slug: "tasks",
      color_hex: "#10B981"
    )
    sign_in user

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-20")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: calendar,
        created_by: user,
        updated_by: user,
        title: "Team standup",
        starts_at_utc: Time.zone.parse("2026-04-12 08:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-12 09:00:00")
      )

      get kalendarium_path(
        workspace_slug: workspace.slug,
        view: "next_7_days",
        date: "2026-04-12",
        window_start: "2026-04-12",
        embedded: "1",
        task_row_id: row.id,
        project_id: tasks_project.id,
        project_scope_id: tasks_project.id,
        view_id: "table-view-1",
        filter_value: "active"
      )
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Choose a slot for")
    expect(response.body).not_to include("Create event")
    expect(response.body).not_to include("Create project")
    expect(response.body).not_to include("Time zones")
    expect(response.body).to include("data-kalendarium-focus-window-start-value=\"2026-04-12\"")
    expect(response.body).to include("data-kalendarium-timeline-initial-focus-minutes-value=\"540\"")

    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css(".notae-kalendarium.is-embedded-split")).to be_present
    expect(document.at_css(".notae-kalendarium-sidebar")).to be_nil
    slot_cards = document.css(".notae-kalendarium-task-slot-form")
    expect(slot_cards.size).to eq(4)
    expect(slot_cards.map { |card| card.at_css(".notae-kalendarium-task-slot-candidate")["data-start-local"] }).to eq(
      [
        "2026-04-13T09:00",
        "2026-04-14T09:00",
        "2026-04-15T09:00",
        "2026-04-16T09:00"
      ]
    )
    first_button = slot_cards.first.at_css(".notae-kalendarium-task-slot-candidate")
    expect(first_button["data-start-local"]).to eq("2026-04-13T09:00")
    expect(first_button["data-end-local"]).to eq("2026-04-13T09:20")
    expect(first_button.at_css("strong")&.text.to_s.squish).to eq("9:00 AM - 9:20 AM")

    editor_form = document.at_css("form[action='#{confirm_schedule_in_kalendarium_database_db_row_path(workspace_slug: workspace.slug, database_id: database.id, id: row.id)}']")
    expect(editor_form).to be_present
    expect(editor_form["data-turbo"]).to eq("false")
    expect(editor_form.at_css("input[name='view_id']")["value"]).to eq("table-view-1")
    expect(editor_form.at_css("input[name='filter_value']")["value"]).to eq("active")
    calendar_filter_form = document.at_css("form.notae-kalendarium-calendar-filter")
    expect(calendar_filter_form).to be_present
    expect(calendar_filter_form["data-turbo"]).to eq("false")
    expect(calendar_filter_form.at_css("input[name='embedded']")["value"]).to eq("1")
    expect(document.at_css("[data-kalendarium-task-slot-target='dialog']")).to be_present
  end

  it "renders a compact embedded widget with a modal create flow" do
    user, workspace, calendar = build_stack(suffix: "widget", time_zone: "Australia/Melbourne")
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Monthly planning",
      starts_at_utc: Time.zone.parse("2026-04-11 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-04-11 10:00:00")
    )
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      embedded: "1",
      widget: "1",
      view: "month",
      date: "2026-04-11"
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    kalendarium_shell = document.at_css(".notae-kalendarium.is-widget")
    create_button = document.at_css("button[data-action='kalendarium-focus#openCreateModal']")
    minimize_button = document.at_css("button[data-action='kalendarium-focus#minimizeWidget']")
    create_dialog = document.at_css("dialog[data-kalendarium-focus-target='createDialog']")
    create_form = create_dialog&.at_css("form.notae-kalendarium-event-modal-form[data-controller='kalendarium-event-form']")
    month_cell = document.at_css(".notae-kalendarium-month-cell[data-action='dblclick->kalendarium-focus#quickCreateDay']")
    widget_view_switch = document.css(".notae-kalendarium-widget-view-switch .notae-chip-button")

    expect(kalendarium_shell).to be_present
    expect(kalendarium_shell["data-kalendarium-focus-widget-value"]).to eq("true")
    expect(document.at_css(".notae-kalendarium-widget-head")).to be_present
    expect(document.at_css(".notae-kalendarium-sidebar")).to be_nil
    expect(document.at_css(".notae-kalendarium-filter-controls")).to be_nil
    expect(document.at_css(".notae-kalendarium-widget-view-switch")).to be_present
    expect(widget_view_switch.map { |link| link.text.strip }).to eq(["(1)", "(7)", "(7+)", "(31)", "(365)"])
    expect(widget_view_switch.map { |link| link["aria-label"] }).to eq(["Day", "Week", "Next 7 days", "Month", "Year"])
    expect(create_button).to be_present
    expect(minimize_button).to be_present
    expect(create_dialog).to be_present
    expect(create_form).to be_present
    expect(create_form["action"]).to include("widget=1")
    expect(month_cell).to be_present
    expect(document.text).to include("Monthly planning")
  end

  it "defaults the compact embedded widget to a one-day today view" do
    user, workspace, = build_stack(suffix: "widget-default-day", time_zone: "Australia/Melbourne")
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      embedded: "1",
      widget: "1",
      date: "2026-04-11"
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    active_view_button = document.at_css(".notae-kalendarium-widget-view-switch .notae-chip-button.is-active")
    day_track = document.at_css(".notae-kalendarium-day-track")
    day_timeline = document.at_css(".notae-kalendarium-timeline")

    expect(active_view_button).to be_present
    expect(active_view_button.text.strip).to eq("(1)")
    expect(document.at_css(".notae-kalendarium-month-grid")).to be_nil
    expect(day_timeline["data-kalendarium-timeline-center-current-time-value"]).to eq("true")
    expect(day_timeline["data-kalendarium-timeline-initial-focus-minutes-value"]).to be_nil
    expect(day_track).to be_present
    expect(day_track["data-day-date"]).to eq("2026-04-11")
  end

  it "uses the requested widget timezone for timeline centering and now-line calculations" do
    user, workspace, = build_stack(suffix: "widget-time-zone", time_zone: "UTC")
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      embedded: "1",
      widget: "1",
      date: "2026-04-11",
      tz: [ "Australia/Melbourne" ]
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    day_timeline = document.at_css(".notae-kalendarium-timeline")

    expect(day_timeline).to be_present
    expect(day_timeline["data-kalendarium-timeline-time-zone-value"]).to eq("Australia/Melbourne")
  end

  it "respects the requested widget calendar view" do
    user, workspace, = build_stack(suffix: "widget-year", time_zone: "Australia/Melbourne")
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      embedded: "1",
      widget: "1",
      view: "year",
      date: "2026-04-11"
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    active_view_button = document.at_css(".notae-kalendarium-widget-view-switch .notae-chip-button.is-active")

    expect(active_view_button).to be_present
    expect(active_view_button.text.strip).to eq("(365)")
    expect(document.at_css(".notae-kalendarium-year-grid")).to be_present
    expect(document.at_css(".notae-kalendarium-month-grid")).to be_nil
  end

  it "shows the current user's Tasks blockouts from other workspaces" do
    user = User.create!(email: "kal-request-cross-workspace@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Kal Request cross workspace", slug: "kal-request-cross-workspace")
    other_workspace = Workspace.create!(name: "Kal Request cross workspace other", slug: "kal-request-cross-workspace-other")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    other_tasks_project = Kalendarium::TasksProjectEnsurer.new(workspace: other_workspace, actor: user).call
    other_user = User.create!(email: "kal-request-cross-workspace-other-user@example.com", password: "password123", time_zone: "UTC")
    Membership.create!(workspace: other_workspace, user: other_user, role: :owner)

    visible_event = KalendariumEvent.create!(
      workspace: other_workspace,
      kalendarium_calendar: other_tasks_project.kalendarium_calendar,
      kalendarium_project: other_tasks_project,
      created_by: user,
      updated_by: user,
      title: "Review roadmap",
      starts_at_utc: Time.zone.parse("2026-04-13 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-04-13 09:20:00")
    )
    KalendariumEvent.create!(
      workspace: other_workspace,
      kalendarium_calendar: other_tasks_project.kalendarium_calendar,
      kalendarium_project: other_tasks_project,
      created_by: other_user,
      updated_by: other_user,
      title: "Someone else's task block",
      starts_at_utc: Time.zone.parse("2026-04-13 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-04-13 10:20:00")
    )
    sign_in user

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-04-13")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    page_text = document.text

    expect(page_text).to include("Review roadmap")
    expect(page_text).not_to include("Someone else's task block")
    expect(response.body).to include(kalendarium_event_path(workspace_slug: other_workspace.slug, id: visible_event.id))
  end

  it "renders suggested slots in the viewer time zone instead of pinning them to midnight" do
    user, workspace, = build_stack(suffix: "task-slots-melbourne", time_zone: "Australia/Melbourne")
    database = Database.create!(workspace: workspace, created_by: user, name: "Task Grid")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    row = DbRow.create!(workspace: workspace, database: database, title: "Buy groceries")
    tasks_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Tasks",
      color_hex: "#10B981",
      time_zone: "Australia/Melbourne",
      source_kind: "project"
    )
    tasks_project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: tasks_calendar,
      name: "Tasks",
      slug: "tasks",
      color_hex: "#10B981"
    )
    sign_in user

    melbourne = ActiveSupport::TimeZone["Australia/Melbourne"]
    travel_to melbourne.parse("2026-04-12 15:37:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-18")

      get kalendarium_path(
        workspace_slug: workspace.slug,
        view: "next_7_days",
        date: "2026-04-12",
        window_start: "2026-04-12",
        embedded: "1",
        task_row_id: row.id,
        project_id: tasks_project.id,
        project_scope_id: tasks_project.id
      )
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-kalendarium-timeline-initial-focus-minutes-value=\"940\"")

    document = Nokogiri::HTML.parse(response.body)
    first_card = document.at_css(".notae-kalendarium-task-slot-form")
    expect(first_card).to be_present
    expect(first_card["style"]).to include("top: 877.33px")
    first_button = first_card.at_css(".notae-kalendarium-task-slot-candidate")
    expect(first_button.at_css("strong")&.text.to_s.squish).to eq("3:40 PM - 4:00 PM")
    expect(first_button["data-start-local"]).to eq("2026-04-12T15:40")
  end

  it "hides the create event accordion in embedded split mode even without a selected task" do
    user, workspace, = build_stack(suffix: "embedded-no-create", time_zone: "UTC")
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "next_7_days",
      date: "2026-04-12",
      window_start: "2026-04-12",
      embedded: "1"
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css(".notae-kalendarium.is-embedded-split")).to be_present
    expect(document.at_css(".notae-kalendarium-sidebar")).to be_nil
    expect(document.at_css(".notae-kalendarium-sidebar-accordion-summary")&.text.to_s).not_to include("Create event")
    expect(document.at_css("[data-kalendarium-focus-target='createAccordion']")).to be_nil
    expect(document.at_css(".notae-kalendarium-task-schedule-panel")).to be_nil
  end

  it "scopes visible project events without persisting that filter to later requests" do
    user, workspace, calendar = build_stack(suffix: "project-scope")
    tasks_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Tasks",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "project"
    )
    tasks_project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: tasks_calendar,
      name: "Tasks",
      slug: "tasks",
      color_hex: "#10B981"
    )
    other_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Roadmap",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project"
    )
    other_project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: other_calendar,
      name: "Roadmap",
      slug: "roadmap",
      color_hex: "#8B5CF6"
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: tasks_calendar,
      kalendarium_project: tasks_project,
      created_by: user,
      updated_by: user,
      title: "Tasks event",
      starts_at_utc: Time.zone.parse("2026-03-18 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-18 09:30:00")
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: other_calendar,
      kalendarium_project: other_project,
      created_by: user,
      updated_by: user,
      title: "Roadmap event",
      starts_at_utc: Time.zone.parse("2026-03-18 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-18 10:30:00")
    )
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "week",
      date: "2026-03-18",
      project_id: tasks_project.id,
      project_scope_id: tasks_project.id
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tasks event")
    expect(response.body).not_to include("Roadmap event")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-18")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Tasks event")
    expect(response.body).to include("Roadmap event")
  end

  it "ships dark theme contrast overrides for kalendarium controls and cards" do
    user, workspace, calendar = build_stack(suffix: "dark-contrast", theme_preference: "dark")
    sign_in user

    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: calendar,
      name: "Roadmap",
      slug: "roadmap",
      color_hex: "#10B981"
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      kalendarium_project: project,
      created_by: user,
      updated_by: user,
      title: "Dark contrast review",
      description: "Contrast audit event",
      starts_at_utc: Time.zone.parse("2026-03-18 09:30:00"),
      ends_at_utc: Time.zone.parse("2026-03-18 10:30:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-17")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-theme-dark")
    document = Nokogiri::HTML.parse(response.body)
    expect(document.at_css(".notae-kalendarium-date-label")).to be_present
    expect(document.at_css(".notae-kalendarium-sidebar-accordion-summary")).to be_present
    expect(document.at_css(".notae-kalendarium-month-weekday")).to be_present
    expect(document.at_css(".notae-kalendarium-event-card")).to be_present
    expect(document.at_css(".notae-kalendarium-project-action-link.is-toggle")).to be_present

    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
    expect(stylesheet).to include("color: var(--notae-text, #292524);")
    expect(stylesheet).to include(".notae-kalendarium-week-header-days .notae-kalendarium-day-focus-link.is-selected strong")
    expect(stylesheet).to include(".notae-kalendarium-project-action-link.is-toggle.is-active")
    expect(stylesheet).to include(".notae-kalendarium-workspace-filter::after")
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
    expect(response.body).to include("data-kalendarium-event-modal-event-title-value=\"Timeline event\"")
    expect(response.body).to include("notae-kalendarium-event-delete-button")
    expect(response.body).to include("notae-kalendarium-event-delete-form")
    document = Nokogiri::HTML.parse(response.body)
    day_track = document.at_css(".notae-kalendarium-day-track")
    expect(day_track).to be_present
    expect(day_track["data-action"]).to include("dblclick->kalendarium-timeline#quickCreate")
    expect(day_track["data-day-date"]).to eq("2026-03-01")
    expect(document.at_css("[data-kalendarium-focus-target='createStartInput']")).to be_present
    expect(document.at_css("[data-kalendarium-focus-target='createEndInput']")).to be_present
    timeline_event = document.at_css(".notae-kalendarium-day-track .notae-kalendarium-event-card.is-timeline")
    expect(timeline_event).to be_present
    expect(timeline_event["data-start-minutes"]).to eq("570")
    expect(timeline_event["data-end-minutes"]).to eq("630")
    modal_heading = document.at_css(".notae-kalendarium-event-modal [data-kalendarium-event-modal-target='heading']")
    expect(modal_heading&.text.to_s.strip).to eq("Timeline event")

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
    document = Nokogiri::HTML.parse(response.body)
    week_track = document.at_css(".notae-kalendarium-week-day-track[data-day-date='2026-03-01']")
    expect(week_track).to be_present
    expect(week_track["data-action"]).to include("dblclick->kalendarium-timeline#quickCreate")

    get kalendarium_path(workspace_slug: workspace.slug, view: "next_7_days", date: "2026-03-18", window_start: "2026-03-18")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h2>Next 7 days</h2>")
    expect(response.body).to include("Mar 18 - Mar 24, 2026")
    expect(response.body).to include("data-kalendarium-focus-view-value=\"next_7_days\"")
    expect(response.body).to include("data-kalendarium-focus-window-start-value=\"2026-03-18\"")
    expect(response.body).to include("date=2026-03-18&amp;view=day")
    expect(response.body).to include("window_start=2026-03-18")
    document = Nokogiri::HTML.parse(response.body)
    rolling_week_tracks = document.css(".notae-kalendarium-week-day-track").map { |track| track["data-day-date"] }
    expect(rolling_week_tracks.first).to eq("2026-03-18")
    expect(rolling_week_tracks.last).to eq("2026-03-24")
    expect(rolling_week_tracks).to include("2026-03-18", "2026-03-24")

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

  it "keeps the desktop week view columns fluid inside the calendar panel" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-kalendarium-week-header-days {\n  display: grid;\n  grid-template-columns: repeat(7, minmax(0, 1fr));")
    expect(stylesheet).to include(".notae-kalendarium-week-columns {\n  display: grid;\n  grid-template-columns: repeat(7, minmax(0, 1fr));")
    expect(stylesheet).to include(".notae-kalendarium-week-day-track {\n  border-right: 1px solid var(--notae-border, #d6d3d1);\n  min-width: 0;")
    expect(stylesheet).to include(".notae-kalendarium-week-header-days strong {\n  font-size: 0.78rem;\n  color: var(--notae-text, #292524);\n  overflow: hidden;")
    expect(stylesheet).to include(".notae-kalendarium-event-delete-button {\n  width: 100%;")
    expect(stylesheet).to include(".notae-kalendarium-event-delete-form {\n  width: 100%;")
    expect(stylesheet).to include("background: #dc2626;")
    expect(stylesheet).to include(".notae-kalendarium-draft-preview {")
    expect(stylesheet).to include(".notae-kalendarium-draft-preview-conflict {")
    expect(stylesheet).to include(".notae-kalendarium-draft-preview.is-dragging {")
    expect(stylesheet).to include("cursor: grab;")
    expect(stylesheet).to include(".notae-kalendarium-project-card header {\n  display: flex;\n  align-items: center;\n  justify-content: space-between;\n  gap: 0.55rem;\n  padding-bottom: 0.45rem;")
  end

  it "keeps the create rail outside the main calendar column on large screens" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-kalendarium {\n  display: grid;\n  grid-template-columns: minmax(0, 1fr) minmax(280px, 320px);")
    expect(stylesheet).to include(".notae-kalendarium-grid {\n  display: contents;\n}")
    expect(stylesheet).to include(".notae-kalendarium-sidebar {\n  grid-column: 2;\n  grid-row: 1 / span 2;")
    expect(stylesheet).to include("@media (min-width: 1501px)")
    expect(stylesheet).to include(".notae-content.notae-content-kalendarium {\n    padding-inline: clamp(0.45rem, 0.9vw, 0.8rem);")
    expect(stylesheet).to include(".notae-kalendarium {\n    grid-template-columns: minmax(0, 1fr) minmax(280px, 320px);")
  end

  it "stacks each project title above its actions inside the projects filter popover" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-kalendarium-project-option-row {\n  display: flex;\n  flex-direction: column;\n  align-items: stretch;")
    expect(stylesheet).to include(".notae-kalendarium-project-option-label {\n  display: block;\n  min-width: 0;\n  overflow: hidden;\n  text-overflow: ellipsis;\n  white-space: nowrap;")
    expect(stylesheet).to include(".notae-kalendarium-project-option-actions {\n  display: flex;\n  flex-wrap: wrap;\n  align-items: center;\n  gap: 0.26rem;\n  padding-left: 1rem;")
  end

  it "keeps the year-view toggle on its own filter row so projects stays aligned with the other calendar buttons" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include("[data-kalendarium-focus-view-value=\"year\"] .notae-kalendarium-head-row {\n  align-items: flex-start;\n  flex-wrap: wrap;\n}")
    expect(stylesheet).to include("[data-kalendarium-focus-view-value=\"year\"] .notae-kalendarium-filter-controls {\n  flex: 1 0 100%;")
    expect(stylesheet).to include(".notae-kalendarium-filter-controls .notae-kalendarium-year-toggle {\n  flex: 1 0 100%;")
    expect(stylesheet).to include("justify-content: flex-end;")
  end

  it "keeps month event cards and overflow labels inside each day cell" do
    user, workspace, calendar = build_stack(suffix: "month-cell-overflow-containment")
    sign_in user

    4.times do |index|
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: calendar,
        created_by: user,
        updated_by: user,
        title: "Event #{index + 1}",
        description: "very-long-unbroken-content-#{'x' * 120}",
        starts_at_utc: Time.zone.parse("2026-03-01 #{format('%02d', 8 + index)}:00:00"),
        ends_at_utc: Time.zone.parse("2026-03-01 #{format('%02d', 9 + index)}:00:00")
      )
    end

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-month-events")
    expect(response.body).to include("notae-kalendarium-month-overflow-label")
    expect(response.body).to include("+1 more")
  end

  it "renders month view event cards with only title, time, and join link" do
    user, workspace, calendar = build_stack(suffix: "month-compact-card")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Design review",
      description: "Long description snippet that should not appear in the month view card.",
      starts_at_utc: Time.zone.parse("2026-03-02 09:15:00"),
      ends_at_utc: Time.zone.parse("2026-03-02 10:00:00"),
      metadata_json: {
        "meeting_join_url" => "https://meet.google.com/abc-defg-hij"
      }
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    month_card = document.at_css(".notae-kalendarium-month-cell .notae-kalendarium-event-card")
    visible_paragraphs = month_card.css("> p").map { |node| node.text.strip }
    visible_links = month_card.css("> .notae-kalendarium-event-links a").map { |node| node.text.strip }

    expect(month_card).to be_present
    expect(month_card.at_css(".notae-kalendarium-event-header-compact")).to be_present
    expect(month_card.at_css(".notae-kalendarium-event-time-line")&.text.to_s).to include("09:15 - 10:00")
    expect(month_card.text).to include("Design review")
    expect(visible_paragraphs).to eq([ "09:15 - 10:00" ])
    expect(visible_links).to eq([ "Join meeting" ])
  end

  it "shows optional daily event labels in year view when toggled on" do
    user, workspace, calendar = build_stack(suffix: "year-daily-event-labels")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Salesforce Weekly Team Standup",
      starts_at_utc: Time.zone.parse("2026-03-25 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-25 10:00:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Show daily events")
    expect(response.body).not_to include("notae-kalendarium-year-day-event-label")

    get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01", year_daily_events: "1")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-year-day-event-label")
    document = Nokogiri::HTML.parse(response.body)
    day_link = document.at_css("a.notae-kalendarium-year-day[data-day-date='2026-03-25']")
    expect(day_link).to be_present
    expect(day_link.at_css(".notae-kalendarium-year-day-number")&.text.to_s.strip).to eq("25")
    event_label = day_link.at_css(".notae-kalendarium-year-day-event-label")
    expect(event_label).to be_present
    expect(event_label.text).to include("Salesforce")
    expect(event_label["style"]).to include("kal-year-event-color")
    toggle_checkbox = document.at_css("input[type='checkbox'][name='year_daily_events'][value='1']")
    expect(toggle_checkbox).to be_present
    expect(toggle_checkbox["checked"]).to eq("checked")
    expect(day_link["href"]).to include("year_daily_events=1")
  end

  it "shows all-day events across covered days in year view without hiding them behind timed events" do
    user, workspace, calendar = build_stack(suffix: "year-all-day-coverage")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Offsite retreat",
      starts_at_utc: Time.zone.parse("2026-03-25 00:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-27 00:00:00"),
      all_day: true
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Budget review",
      starts_at_utc: Time.zone.parse("2026-03-25 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-25 10:00:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)

    march_twenty_fifth = document.at_css("a.notae-kalendarium-year-day[data-day-date='2026-03-25']")
    expect(march_twenty_fifth).to be_present
    march_twenty_fifth_label = march_twenty_fifth.at_css(".notae-kalendarium-year-day-event-label")
    expect(march_twenty_fifth_label).to be_present
    expect(march_twenty_fifth_label.text).to include("Offsite")
    expect(march_twenty_fifth_label.text).not_to include("+1")

    march_twenty_sixth = document.at_css("a.notae-kalendarium-year-day[data-day-date='2026-03-26']")
    expect(march_twenty_sixth).to be_present
    march_twenty_sixth_label = march_twenty_sixth.at_css(".notae-kalendarium-year-day-event-label")
    expect(march_twenty_sixth_label).to be_present
    expect(march_twenty_sixth_label.text).to include("Offsite")

    march_twenty_seventh = document.at_css("a.notae-kalendarium-year-day[data-day-date='2026-03-27']")
    expect(march_twenty_seventh).to be_present
    expect(march_twenty_seventh.at_css(".notae-kalendarium-year-day-event-label")).to be_nil

    get kalendarium_path(workspace_slug: workspace.slug, view: "year", date: "2026-03-01", year_daily_events: "1")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    march_twenty_fifth = document.at_css("a.notae-kalendarium-year-day[data-day-date='2026-03-25']")
    expect(march_twenty_fifth).to be_present
    march_twenty_fifth_label = march_twenty_fifth.at_css(".notae-kalendarium-year-day-event-label")
    expect(march_twenty_fifth_label).to be_present
    expect(march_twenty_fifth_label.text).to include("Offsite")
    expect(march_twenty_fifth_label.text).to include("+1")
    expect(response.body).to include("2 events")
  end

  it "shows invitees and join links when meeting metadata is available" do
    user, workspace, calendar = build_stack(suffix: "meeting-metadata-render")
    sign_in user

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Team sync",
      starts_at_utc: Time.zone.parse("2026-03-01 09:30:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:30:00"),
      metadata_json: {
        "meeting_join_url" => "https://meet.google.com/abc-defg-hij",
        "invitees" => [
          { "name" => "Alex", "email" => "alex@example.com", "status" => "accepted" },
          { "email" => "sam@example.com" }
        ]
      }
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Join meeting")
    expect(response.body).to include("https://meet.google.com/abc-defg-hij")
    expect(response.body).to include("Invitees")
    expect(response.body).to include("Alex")
    expect(response.body).to include("sam@example.com")
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

  it "renders separate calendar and project dropdown filters with project actions" do
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
      calendar_ids: [ calendar.id ]
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendars (1)")
    expect(response.body).to include("Projects (1)")
    expect(response.body).to include("class=\"notae-kalendarium-calendar-filter\"")
    expect(response.body).to include("class=\"notae-kalendarium-project-filter\"")
    expect(response.body).to include("data-controller=\"floating-panel\"")
    expect(response.body).to include("data-floating-panel-target=\"summary\"")
    expect(response.body).to include("data-floating-panel-target=\"panel\"")
    expect(response.body).to include("class=\"notae-kalendarium-sidebar-accordion-summary\">Create event</summary>")
    expect(response.body).to include("class=\"notae-kalendarium-sidebar-accordion-summary\">Create project</summary>")
    expect(response.body).not_to include("notae-kalendarium-sidebar-accordion-chevron")
    expect(response.body).to include("name=\"calendar_ids[]\"")
    expect(response.body).to include("Show: On")
    expect(response.body).to include("Edit projects")

    document = Nokogiri::HTML.parse(response.body)
    option_row = document.at_css(".notae-kalendarium-project-option-row")
    expect(option_row).to be_present
    option_label = option_row.at_css(".notae-kalendarium-project-option-label")
    expect(option_label).to be_present
    expect(option_label.text).to include(project.name)
    show_link = option_row.at_css("a.notae-kalendarium-project-action-link.is-toggle")
    archive_link = option_row.at_css("a[data-turbo-method='patch']")
    delete_link = option_row.at_css("a[data-turbo-method='delete']")
    expect(show_link).to be_present
    expect(archive_link).to be_present
    expect(delete_link).to be_present
    expect(show_link["href"]).to include("toggle_project_id=#{project.id}")
    expect(archive_link["href"]).to include("/kalendarium/projects/#{project.id}/archive")
    expect(delete_link["href"]).to include("/kalendarium/projects/#{project.id}")
    edit_projects_link = document.at_css(".notae-kalendarium-project-popover-actions a.notae-chip-button")
    expect(edit_projects_link).to be_nil
    edit_projects_link = document.at_css(".notae-kalendarium-project-popover-actions a.notae-kalendarium-project-edit-link")
    expect(edit_projects_link).to be_present
    expect(edit_projects_link.text).to include("Edit projects")
    expect(edit_projects_link["href"]).to include("view=project")
  end

  it "shows a close button in project view that returns to the requested calendar view" do
    user, workspace, = build_stack(suffix: "project-close-button")
    sign_in user

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "project",
      return_view: "day",
      date: "2026-03-01"
    )

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML.parse(response.body)
    close_link = document.at_css(".notae-kalendarium-project-close-button")
    expect(close_link).to be_present
    expect(close_link["href"]).to include("view=day")
    expect(close_link["href"]).to include("date=2026-03-01")
  end

  it "toggles project visibility independently from calendar visibility" do
    user, workspace, calendar = build_stack(suffix: "project-toggle")
    sign_in user

    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Project scope calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project"
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Project Alpha",
      slug: "project-alpha",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar
    )
    regular_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Regular calendar event",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )
    project_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: project_calendar,
      kalendarium_project: project,
      created_by: user,
      updated_by: user,
      title: "Project scoped event",
      starts_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 12:00:00")
    )

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id.to_s ]
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(regular_event.title)
    expect(response.body).to include(project_event.title)

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: "2026-03-01",
      calendar_ids: [ calendar.id.to_s ],
      toggle_project_id: project.id,
      project_visible: "0"
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(regular_event.title)
    expect(response.body).not_to include(project_event.title)
    expect(response.body).to include("Projects (0)")

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: "2026-03-01",
      calendar_ids: [ calendar.id.to_s ]
    )
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(regular_event.title)
    expect(response.body).not_to include(project_event.title)
    expect(response.body).to include("Projects (0)")
  end

  it "persists calendar selections when navigating away and returning to kalendarium" do
    user, workspace, calendar = build_stack(suffix: "persisted-calendar-filter")
    sign_in user

    secondary_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Secondary",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider"
    )

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Primary event",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: secondary_calendar,
      created_by: user,
      updated_by: user,
      title: "Secondary event",
      starts_at_utc: Time.zone.parse("2026-03-01 11:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 12:00:00")
    )

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id ]
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendars (1)")
    expect(response.body).to include("Primary event")
    expect(response.body).not_to include("Secondary event")

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendars (1)")
    expect(response.body).to include("Primary event")
    expect(response.body).not_to include("Secondary event")
  end

  it "self-heals stale calendar selections after calendars are recreated" do
    user, workspace, calendar = build_stack(suffix: "stale-calendar-selection")
    user.update!(time_zone: "UTC")
    sign_in user

    secondary_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Secondary",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider"
    )

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id ]
    )

    calendar.destroy!
    secondary_calendar.destroy!

    replacement_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Replacement",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: replacement_calendar,
      created_by: user,
      updated_by: user,
      title: "Replacement event",
      starts_at_utc: Time.utc(2026, 3, 1, 12, 0, 0),
      ends_at_utc: Time.utc(2026, 3, 1, 13, 0, 0)
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendars (1)")
    expect(response.body).to include("Replacement event")
  end

  it "runs connection sync immediately from the refresh action" do
    user, workspace, = build_stack(suffix: "refresh-action")
    sign_in user

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Public feed",
      ics_url: "https://example.com/feed.ics",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: connection,
      provider: "ics",
      remote_id: "ics-main",
      name: "Public feed",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "month",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id ]
    }

    expect(response).to redirect_to(
      kalendarium_path(workspace_slug: workspace.slug, view: "month", date: Date.parse("2026-03-01"), calendar_ids: [ calendar.id.to_s ])
    )
    expect(flash[:notice]).to include("Refresh completed for 1 calendar in the current view")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(
        connection: connection,
        calendars: [ calendar ],
        retry_pending_writes: false
      )
    )
    expect(sync_service).to have_received(:call)
  end

  it "instantiates the refresh sync service with keyword arguments" do
    user, workspace, = build_stack(suffix: "refresh-keyword-init")
    sign_in user

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Keyword feed",
      ics_url: "https://example.com/keyword.ics",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: connection,
      provider: "ics",
      remote_id: "ics-keyword",
      name: "Keyword feed",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )

    allow_any_instance_of(Kalendarium::ConnectionSyncService).to receive(:call).and_return(true)

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "week",
      date: "2026-03-06",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id ]
    }

    expect(response).to redirect_to(
      kalendarium_path(workspace_slug: workspace.slug, view: "week", date: Date.parse("2026-03-06"), calendar_ids: [ calendar.id.to_s ])
    )
    expect(flash[:notice]).to include("Refresh completed for 1 calendar in the current view")
  end

  it "runs refresh once per active connection and skips disabled ones" do
    user, workspace, = build_stack(suffix: "refresh-queue-count")
    sign_in user

    connection_one = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Feed one",
      ics_url: "https://example.com/one.ics",
      enabled: true,
      status: "connected"
    )
    connection_two = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Feed two",
      ics_url: "https://example.com/two.ics",
      enabled: true,
      status: "connected"
    )
    KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Disabled feed",
      ics_url: "https://example.com/disabled.ics",
      enabled: false,
      status: "disconnected"
    )
    calendar_one = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: connection_one,
      provider: "ics",
      remote_id: "ics-one",
      name: "Feed one",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    calendar_two = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: connection_two,
      provider: "ics",
      remote_id: "ics-two",
      name: "Feed two",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    sync_service_one = instance_double(Kalendarium::ConnectionSyncService, call: true)
    sync_service_two = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service_one, sync_service_two)

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "month",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar_one.id, calendar_two.id ]
    }

    expect(response).to redirect_to(
      kalendarium_path(workspace_slug: workspace.slug, view: "month", date: Date.parse("2026-03-01"), calendar_ids: [ calendar_one.id.to_s, calendar_two.id.to_s ])
    )
    expect(flash[:notice]).to include("Refresh completed for 2 calendars in the current view")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(connection: connection_one, calendars: [ calendar_one ], retry_pending_writes: false)
    )
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(connection: connection_two, calendars: [ calendar_two ], retry_pending_writes: false)
    )
    expect(sync_service_one).to have_received(:call)
    expect(sync_service_two).to have_received(:call)
  end

  it "keeps the refresh selection session compact when many calendars are selected" do
    user, workspace, = build_stack(suffix: "refresh-cookie-overflow")
    sign_in user

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Large feed",
      ics_url: "https://example.com/large.ics",
      enabled: true,
      status: "connected"
    )

    calendars = 80.times.map do |index|
      KalendariumCalendar.create!(
        workspace: workspace,
        created_by: user,
        kalendarium_connection: connection,
        provider: "ics",
        remote_id: "ics-large-#{index}",
        name: "Large feed #{index + 1}",
        color_hex: "#3B82F6",
        time_zone: "UTC",
        source_kind: "provider",
        enabled: true
      )
    end

    selected_calendars = calendars.first(78)
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    expect do
      post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
        view: "week",
        date: "2026-03-06",
        calendar_filter_applied: "1",
        calendar_ids: selected_calendars.map(&:id)
      }
    end.not_to raise_error

    expect(response).to redirect_to(
      kalendarium_path(
        workspace_slug: workspace.slug,
        view: "week",
        date: Date.parse("2026-03-06"),
        calendar_ids: selected_calendars.map { |calendar| calendar.id.to_s }
      )
    )
    expect(flash[:notice]).to include("Refresh completed for 78 calendars in the current view")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(
        connection: connection,
        calendars: match_array(selected_calendars),
        retry_pending_writes: false
      )
    )
    expect(sync_service).to have_received(:call)
  end

  it "skips full-connection refresh for unselected connections when a calendar filter is applied" do
    user, workspace, = build_stack(suffix: "refresh-filter-skip-unselected")
    sign_in user

    selected_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Selected feed",
      ics_url: "https://example.com/selected.ics",
      enabled: true,
      status: "connected"
    )
    unselected_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Unselected feed",
      ics_url: "https://example.com/unselected.ics",
      enabled: true,
      status: "connected"
    )

    selected_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: selected_connection,
      provider: "ics",
      remote_id: "ics-selected",
      name: "Selected feed",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: unselected_connection,
      provider: "ics",
      remote_id: "ics-unselected",
      name: "Unselected feed",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )

    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "week",
      date: "2026-03-01",
      calendar_filter_applied: "1",
      calendar_ids: [ selected_calendar.id ]
    }

    expect(response).to redirect_to(
      kalendarium_path(workspace_slug: workspace.slug, view: "week", date: Date.parse("2026-03-01"), calendar_ids: [ selected_calendar.id.to_s ])
    )
    expect(flash[:notice]).to include("Refresh completed for 1 calendar in the current view")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(connection: selected_connection, calendars: [ selected_calendar ], retry_pending_writes: false)
    )
    expect(Kalendarium::ConnectionSyncService).not_to have_received(:new).with(
      hash_including(connection: unselected_connection)
    )
  end

  it "scopes refresh to the current view range" do
    user, workspace, = build_stack(suffix: "refresh-scope-range")
    sign_in user

    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "Scoped feed",
      ics_url: "https://example.com/scoped.ics",
      enabled: true,
      status: "connected"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_connection: connection,
      provider: "ics",
      remote_id: "ics-scoped",
      name: "Scoped feed",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      enabled: true
    )
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)
    allow(Kalendarium::ConnectionSyncService).to receive(:new).and_return(sync_service)

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "day",
      date: "2026-03-10",
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id ]
    }

    expected_date = Date.parse("2026-03-10")
    expect(Kalendarium::ConnectionSyncService).to have_received(:new).with(
      hash_including(
        connection: connection,
        calendars: [ calendar ],
        range_start: expected_date.beginning_of_day,
        range_end: expected_date.end_of_day,
        retry_pending_writes: false
      )
    )
  end

  it "shows an alert when refresh is triggered with no active connections" do
    user, workspace, calendar = build_stack(suffix: "refresh-no-connections")
    sign_in user

    post refresh_kalendarium_path(workspace_slug: workspace.slug), params: {
      view: "month",
      date: "2026-03-01",
      calendar_ids: [ calendar.id ]
    }

    expect(response).to redirect_to(
      kalendarium_path(workspace_slug: workspace.slug, view: "month", date: Date.parse("2026-03-01"), calendar_ids: [ calendar.id.to_s ])
    )
    expect(flash[:alert]).to include("No connected calendars are available to refresh.")
  end

  it "shows google and icloud calendars together while excluding project calendars from the calendar filter" do
    user, workspace, calendar = build_stack(suffix: "provider-filter-split")
    sign_in user

    calendar.update!(name: "Google Team", provider: "google")
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "iCloud Family",
      provider: "icloud_caldav",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "provider"
    )
    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Project Hidden Calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project"
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Project Hidden",
      slug: "project-hidden",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: project_calendar,
      kalendarium_project: project,
      created_by: user,
      updated_by: user,
      title: "Project-only event",
      starts_at_utc: Time.zone.parse("2026-03-10 10:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-10 11:00:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "month", date: "2026-03-01")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Project-only event")
    document = Nokogiri::HTML.parse(response.body)
    filter_labels = document.css(".notae-kalendarium-calendar-filter .notae-options-checkbox span").map(&:text)
    expect(filter_labels).to include("Google Team")
    expect(filter_labels).to include("iCloud Family")
    expect(filter_labels).not_to include("Project Hidden Calendar")
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

  it "renders all-day events in a top strip and staggers overlapping timed events" do
    user, workspace, calendar = build_stack(suffix: "all-day-overlap")
    sign_in user

    all_day_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "All day planning",
      all_day: true,
      starts_at_utc: Time.zone.parse("2026-03-01 00:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 23:59:00")
    )
    first_overlap = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Overlap one",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:30:00")
    )
    second_overlap = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Overlap two",
      starts_at_utc: Time.zone.parse("2026-03-01 09:15:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:45:00")
    )

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-all-day-strip")

    day_doc = Nokogiri::HTML.parse(response.body)
    all_day_card = day_doc.at_css("#kalendarium_event_#{all_day_event.id}")
    expect(all_day_card["class"]).to include("is-all-day")
    expect(all_day_card["class"]).not_to include("is-timeline")

    first_card = day_doc.at_css("#kalendarium_event_#{first_overlap.id}")
    second_card = day_doc.at_css("#kalendarium_event_#{second_overlap.id}")
    expect(first_card["class"]).to include("is-timeline")
    expect(second_card["class"]).to include("is-timeline")
    expect(first_card["style"]).to include("left: calc(")
    expect(first_card["style"]).to include("width: calc(")
    expect(second_card["style"]).to include("left: calc(")
    expect(second_card["style"]).to include("width: calc(")

    get kalendarium_path(workspace_slug: workspace.slug, view: "week", date: "2026-03-01")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-kalendarium-all-day-strip")
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

  it "archives a project, hides it from active views, and disables its project calendar" do
    user, workspace, calendar = build_stack(suffix: "project-archive")
    sign_in user
    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Project calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project",
      enabled: true
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Archived soon",
      slug: "archived-soon",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      kalendarium_project: project,
      created_by: user,
      updated_by: user,
      title: "Project event to hide",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )

    patch archive_kalendarium_project_path(workspace_slug: workspace.slug, id: project.id), params: {
      view: "day",
      date: "2026-03-01"
    }

    expect(response).to redirect_to(kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01"))
    expect(project.reload).to be_archived
    expect(project_calendar.reload.enabled).to be(false)

    get kalendarium_path(workspace_slug: workspace.slug, view: "project", date: "2026-03-01")
    document = Nokogiri::HTML.parse(response.body)
    expect(response.body).to include("Archived projects")
    expect(response.body).to include("Archived soon")
    edit_projects_link = document.at_css(".notae-kalendarium-project-popover-actions a.notae-kalendarium-project-edit-link")
    expect(edit_projects_link).to be_present
    expect(edit_projects_link.text).to include("Edit projects")

    get kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01")
    expect(response.body).not_to include("Project event to hide")
    expect(response.body).to include("Projects (0)")
  end

  it "restores an archived project and re-enables its project calendar" do
    user, workspace, = build_stack(suffix: "project-unarchive")
    sign_in user
    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Project calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project",
      enabled: false
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Bring back",
      slug: "bring-back",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar,
      archived_at: 2.days.ago
    )

    patch unarchive_kalendarium_project_path(workspace_slug: workspace.slug, id: project.id), params: {
      view: "project",
      date: "2026-03-01"
    }

    expect(response).to redirect_to(kalendarium_path(workspace_slug: workspace.slug, view: "project", date: "2026-03-01", project_id: project.id))
    expect(project.reload.archived_at).to be_nil
    expect(project_calendar.reload.enabled).to be(true)

    get kalendarium_path(workspace_slug: workspace.slug, view: "project", date: "2026-03-01")
    expect(response.body).to include("Bring back")
  end

  it "deletes a project, unassigns its events, and disables its project calendar" do
    user, workspace, calendar = build_stack(suffix: "project-delete")
    sign_in user
    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Delete calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project",
      enabled: true
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Delete me",
      slug: "delete-me",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      kalendarium_project: project,
      created_by: user,
      updated_by: user,
      title: "Project event to unassign",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00")
    )

    delete kalendarium_project_path(workspace_slug: workspace.slug, id: project.id), params: {
      view: "project",
      date: "2026-03-01"
    }

    expect(response).to redirect_to(kalendarium_path(workspace_slug: workspace.slug, view: "project", date: "2026-03-01"))
    expect(KalendariumProject.where(id: project.id)).to be_empty
    expect(event.reload.kalendarium_project_id).to be_nil
    expect(project_calendar.reload.enabled).to be(false)
  end

  it "creates all-day events with optional quick Nota links and rejects invalid or past end times" do
    user, workspace, calendar = build_stack(suffix: "event-create")
    sign_in user

    future_start = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    future_end = future_start + 1.hour
    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      kalendarium_event: {
        kalendarium_calendar_id: calendar.id,
        title: "Planning",
        starts_at_local: future_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: future_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        all_day: "1",
        linked_page_action: "create_page",
        reminder_offsets_minutes: %w[10 30]
      }
    }

    created_event = KalendariumEvent.order(:created_at).last
    expect(created_event.title).to eq("Planning")
    expect(created_event.linked_page).to be_present
    expect(created_event.all_day).to be(true)
    expect(created_event.reminder_offsets_minutes).to eq([ 10, 30 ])
    expect(created_event.starts_at_utc.in_time_zone(user.time_zone).strftime("%H:%M")).to eq("00:00")
    expect(created_event.ends_at_utc.in_time_zone(user.time_zone).strftime("%H:%M")).to eq("23:59")

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

    past_start = 2.hours.ago.change(sec: 0)
    past_end = 1.hour.ago.change(sec: 0)
    expect do
      post kalendarium_events_path(workspace_slug: workspace.slug), params: {
        kalendarium_event: {
          kalendarium_calendar_id: calendar.id,
          title: "Already finished",
          starts_at_local: past_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
          ends_at_local: past_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
        }
      }
    end.not_to change(KalendariumEvent, :count)

    expect(flash[:alert]).to include("must be in the future")
  end

  it "persists the event Google Meet extension preference from create and update flows" do
    user, workspace, calendar = build_stack(suffix: "event-capture-toggle")
    sign_in user

    start_at = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    end_at = start_at + 1.hour
    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      kalendarium_event: {
        kalendarium_calendar_id: calendar.id,
        title: "Capture me",
        starts_at_local: start_at.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: end_at.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        meeting_capture_enabled: "1"
      }
    }

    event = KalendariumEvent.order(:created_at).last
    expect(event.meeting_capture_enabled).to be(true)

    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      kalendarium_event: {
        kalendarium_calendar_id: calendar.id,
        title: "Capture defaults off",
        starts_at_local: (start_at + 1.day).in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: (end_at + 1.day).in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
      }
    }

    expect(KalendariumEvent.find_by!(title: "Capture defaults off").meeting_capture_enabled).to be(false)

    patch kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: {
      view: "day",
      date: start_at.to_date.to_s,
      kalendarium_event: {
        meeting_capture_enabled: "0"
      }
    }

    expect(event.reload.meeting_capture_enabled).to be(false)

    get kalendarium_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Prefer this event when the Google Meet extension starts a transcript")
  end

  it "uses project calendars and project colors for project-linked events" do
    user, workspace, calendar = build_stack(suffix: "project-event-color")
    sign_in user

    project_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Project Color Calendar",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project"
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      name: "Project Purple",
      slug: "project-purple",
      color_hex: "#8B5CF6",
      kalendarium_calendar: project_calendar
    )

    future_start = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    future_end = future_start + 1.hour
    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      view: "day",
      date: future_start.to_date.to_s,
      kalendarium_event: {
        kalendarium_calendar_id: calendar.id,
        kalendarium_project_id: project.id,
        title: "Project colored event",
        starts_at_local: future_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: future_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
      }
    }

    event = KalendariumEvent.order(:created_at).last
    expect(event.kalendarium_project_id).to eq(project.id)
    expect(event.kalendarium_calendar_id).to eq(project_calendar.id)

    get kalendarium_path(
      workspace_slug: workspace.slug,
      view: "day",
      date: future_start.to_date.to_s,
      calendar_filter_applied: "1",
      calendar_ids: [ calendar.id.to_s ]
    )

    document = Nokogiri::HTML.parse(response.body)
    event_card = document.at_css("#kalendarium_event_#{event.id}")
    expect(event_card).to be_present
    expect(event_card["style"]).to include("--kal-color: #8B5CF6")
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

  it "syncs provider-backed events to remote on create, update and delete" do
    user, workspace, = build_stack(suffix: "provider-event-sync")
    sign_in user
    create_start = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    create_end = create_start + 1.hour
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google sync",
      access_token: "token",
      enabled: true,
      status: "connected"
    )
    provider_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Google primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )

    create_sync_service = instance_double(Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    update_sync_service = instance_double(Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    delete_sync_service = instance_double(Kalendarium::ProviderEventSyncService, delete_remote!: true)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).and_return(
      create_sync_service,
      update_sync_service,
      delete_sync_service
    )

    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      view: "day",
      date: "2026-03-01",
      kalendarium_event: {
        kalendarium_calendar_id: provider_calendar.id,
        title: "Provider event",
        starts_at_local: create_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: create_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
      }
    }
    event = KalendariumEvent.order(:created_at).last
    expect(create_sync_service).to have_received(:upsert_remote!)

    patch kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: {
      view: "day",
      date: "2026-03-01",
      kalendarium_event: {
        title: "Provider event updated",
        starts_at_local: "2026-03-01T10:30",
        ends_at_local: "2026-03-01T11:30"
      }
    }
    expect(update_sync_service).to have_received(:upsert_remote!)

    delete kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: {
      view: "day",
      date: "2026-03-01"
    }
    expect(delete_sync_service).to have_received(:delete_remote!)
  end

  it "allows event creation for legacy writable iCloud calendars that were previously marked read-only" do
    user, workspace, = build_stack(suffix: "legacy-icloud-writable")
    sign_in user
    create_start = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    create_end = create_start + 1.hour
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud sync",
      provider_username: "apple-id@example.com",
      provider_password: "abcd-efgh-ijkl-mnop",
      enabled: true,
      status: "connected"
    )
    provider_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "icloud_caldav",
      remote_id: "/123/calendars/home/",
      name: "iCloud Home",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: true,
      enabled: true,
      metadata_json: { "subscribed" => false }
    )

    sync_service = instance_double(Kalendarium::ProviderEventSyncService, upsert_remote!: true)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).and_return(sync_service)

    expect do
      post kalendarium_events_path(workspace_slug: workspace.slug), params: {
        view: "day",
        date: "2026-03-01",
        kalendarium_event: {
          kalendarium_calendar_id: provider_calendar.id,
          title: "Legacy iCloud write",
          starts_at_local: create_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
          ends_at_local: create_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
        }
      }
    end.to change(KalendariumEvent, :count).by(1)

    expect(response).to redirect_to(kalendarium_path(workspace_slug: workspace.slug, view: "day", date: "2026-03-01"))
    expect(sync_service).to have_received(:upsert_remote!)
  end

  it "marks provider-backed events as pending remote sync when immediate write fails" do
    user, workspace, = build_stack(suffix: "provider-sync-pending")
    sign_in user
    create_start = 2.days.from_now.change(hour: 10, min: 0, sec: 0)
    create_end = create_start + 1.hour
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google sync",
      access_token: "token",
      enabled: true,
      status: "connected"
    )
    provider_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Google primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )

    provider_sync = instance_double(Kalendarium::ProviderEventSyncService)
    allow(provider_sync).to receive(:upsert_remote!).and_raise(RuntimeError, "Insufficient permissions")
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).and_return(provider_sync)

    post kalendarium_events_path(workspace_slug: workspace.slug), params: {
      view: "day",
      date: "2026-03-01",
      kalendarium_event: {
        kalendarium_calendar_id: provider_calendar.id,
        title: "Provider sync pending",
        starts_at_local: create_start.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M"),
        ends_at_local: create_end.in_time_zone(user.time_zone).strftime("%Y-%m-%dT%H:%M")
      }
    }

    event = KalendariumEvent.order(:created_at).last
    expect(flash[:alert]).to include("Event saved locally, but remote sync failed")
    expect(event.metadata_json["pending_remote_sync"]).to eq(true)
    expect(event.metadata_json["pending_remote_sync_error"]).to include("Insufficient permissions")
  end

  it "does not delete a provider-backed event locally when remote delete fails" do
    user, workspace, = build_stack(suffix: "provider-delete-fail")
    sign_in user
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Google sync",
      access_token: "token",
      enabled: true,
      status: "connected"
    )
    provider_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Google primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: provider_calendar,
      created_by: user,
      updated_by: user,
      title: "Provider delete failure",
      starts_at_utc: Time.zone.parse("2026-03-01 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-01 10:00:00"),
      source_kind: "provider",
      remote_event_id: "remote-event-1"
    )

    sync_service = instance_double(Kalendarium::ProviderEventSyncService)
    allow(Kalendarium::ProviderEventSyncService).to receive(:new).and_return(sync_service)
    allow(sync_service).to receive(:delete_remote!).and_raise(RuntimeError, "Google Calendar request failed (500): Upstream error")

    expect do
      delete kalendarium_event_path(workspace_slug: workspace.slug, id: event.id), params: {
        view: "day",
        date: "2026-03-01"
      }
    end.not_to change(KalendariumEvent, :count)

    expect(flash[:alert]).to include("Could not delete remote event")
    expect(event.reload).to be_present
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
