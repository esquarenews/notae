require "rails_helper"

RSpec.describe Kalendarium::TaskSchedulingService do
  include ActiveSupport::Testing::TimeHelpers

  def build_stack(suffix:)
    user = User.create!(email: "kal-task-scheduler-#{suffix}@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Kal Task Scheduler #{suffix}", slug: "kal-task-scheduler-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    database = Database.create!(workspace: workspace, created_by: user, name: "Task Grid")
    date_created_property = DbProperty.create!(workspace: workspace, database: database, name: "Date created", property_type: :date)
    due_date_property = DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    status_property = DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)
    row = DbRow.create!(workspace: workspace, database: database, title: "Review launch plan")

    [ user, workspace, database, row, date_created_property, due_date_property, status_property ]
  end

  it "schedules urgent work tasks into weekday work hours over the next two working days" do
    user, workspace, _database, row, date_created_property, due_date_property, status_property = build_stack(suffix: "slot")
    busy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    travel_to Time.zone.parse("2026-04-12 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-20")
      DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "not started")

      service = described_class.new(workspace: workspace, row: row, actor: user)
      candidate_result = service.candidate_slots(limit: 4)
      chosen_slot = candidate_result.slots.first
      event = service.build_event(starts_at: chosen_slot.starts_at, ends_at: chosen_slot.ends_at)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.size).to eq(4)
      expect(candidate_result.slots.map { |slot| [ slot.starts_at.in_time_zone("UTC").strftime("%F %H:%M"), slot.ends_at.in_time_zone("UTC").strftime("%F %H:%M") ] }).to eq(
        [
          [ "2026-04-13 09:00", "2026-04-13 09:20" ],
          [ "2026-04-14 09:00", "2026-04-14 09:20" ],
          [ "2026-04-13 10:20", "2026-04-13 10:40" ],
          [ "2026-04-14 10:20", "2026-04-14 10:40" ]
        ]
      )
      expect(event.kalendarium_project.name).to eq("Tasks")
      expect(event.linked_db_row).to eq(row)
      expect(event.starts_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:00")
      expect(event.ends_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:20")
    end
  end

  it "schedules personal tasks after hours on weekdays" do
    user, workspace, _database, row, date_created_property, due_date_property, status_property = build_stack(suffix: "personal")
    row.update!(title: "Buy groceries")

    travel_to Time.zone.parse("2026-04-13 10:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-13")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")
      DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")

      candidate_result = described_class.new(workspace: workspace, row: row, actor: user).candidate_slots(limit: 4)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.map { |slot| slot.starts_at.in_time_zone("UTC").strftime("%F %H:%M") }).to eq(
        [
          "2026-04-13 18:00",
          "2026-04-14 18:00",
          "2026-04-15 18:00",
          "2026-04-16 18:00"
        ]
      )
    end
  end

  it "prefers slots with a 15-minute buffer around short events" do
    user, workspace, _database, row, date_created_property, due_date_property, status_property = build_stack(suffix: "buffer")
    busy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    travel_to Time.zone.parse("2026-04-13 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-13")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")
      DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: busy_calendar,
        created_by: user,
        updated_by: user,
        title: "Standup",
        starts_at_utc: Time.zone.parse("2026-04-13 09:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-13 09:20:00")
      )

      candidate_result = described_class.new(workspace: workspace, row: row, actor: user).candidate_slots(limit: 1)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.first.starts_at.in_time_zone("UTC").strftime("%F %H:%M")).to eq("2026-04-13 09:35")
    end
  end

  it "ignores all-day events when finding timed task slots" do
    user, workspace, _database, row, date_created_property, due_date_property, status_property = build_stack(suffix: "all-day")
    busy_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    travel_to Time.zone.parse("2026-04-13 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-13")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")
      DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: busy_calendar,
        created_by: user,
        updated_by: user,
        title: "Working elsewhere",
        starts_at_utc: Time.zone.parse("2026-04-13 00:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-14 00:00:00"),
        all_day: true
      )

      candidate_result = described_class.new(workspace: workspace, row: row, actor: user).candidate_slots(limit: 1)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.first.starts_at.in_time_zone("UTC").strftime("%F %H:%M")).to eq("2026-04-13 09:00")
    end
  end

  it "only considers calendars in the visible scope" do
    user, workspace, _database, row, date_created_property, due_date_property, status_property = build_stack(suffix: "visible-scope")
    visible_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Visible",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    hidden_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Hidden",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "local"
    )

    travel_to Time.zone.parse("2026-04-13 08:10:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-13")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-25")
      DbCell.create!(workspace: workspace, db_row: row, db_property: status_property, value_text: "started")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: hidden_calendar,
        created_by: user,
        updated_by: user,
        title: "Hidden meeting",
        starts_at_utc: Time.zone.parse("2026-04-13 09:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-13 17:00:00")
      )

      candidate_result = described_class.new(
        workspace: workspace,
        row: row,
        actor: user,
        busy_calendar_ids: [ visible_calendar.id ]
      ).candidate_slots(limit: 1)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.first.starts_at.in_time_zone("UTC").strftime("%F %H:%M")).to eq("2026-04-13 09:00")
    end
  end

  it "returns an error when no slot fits before the task deadline" do
    user, workspace, _database, row, date_created_property, due_date_property, = build_stack(suffix: "deadline")

    travel_to Time.zone.parse("2026-04-12 17:50:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-12")

      result = described_class.new(workspace: workspace, row: row, actor: user).call

      expect(result).not_to be_success
      expect(result.error).to include("No open 20-minute slot is available in weekday work hours over the next 7 days before this task's deadline.")
      expect(result.error).to include('This task is being treated as a work task with status "unset"')
      expect(result.error).to include("Scheduling checks all enabled calendars, not only the ones currently visible in the split view.")
    end
  end
end
