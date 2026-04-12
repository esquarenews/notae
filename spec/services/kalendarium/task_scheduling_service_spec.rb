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
    row = DbRow.create!(workspace: workspace, database: database, title: "Review launch plan")

    [ user, workspace, database, row, date_created_property, due_date_property ]
  end

  it "finds a few open 20-minute slots and can build an event for a chosen one" do
    user, workspace, _database, row, date_created_property, due_date_property = build_stack(suffix: "slot")
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
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-13")
      KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: busy_calendar,
        created_by: user,
        updated_by: user,
        title: "Team standup",
        starts_at_utc: Time.zone.parse("2026-04-12 08:00:00"),
        ends_at_utc: Time.zone.parse("2026-04-12 09:00:00")
      )

      service = described_class.new(workspace: workspace, row: row, actor: user)
      candidate_result = service.candidate_slots(limit: 3)
      chosen_slot = candidate_result.slots.first
      event = service.build_event(starts_at: chosen_slot.starts_at, ends_at: chosen_slot.ends_at)

      expect(candidate_result).to be_success
      expect(candidate_result.slots.size).to eq(3)
      expect(candidate_result.slots.map { |slot| [ slot.starts_at.in_time_zone("UTC").strftime("%H:%M"), slot.ends_at.in_time_zone("UTC").strftime("%H:%M") ] }).to eq(
        [
          [ "09:00", "09:20" ],
          [ "09:20", "09:40" ],
          [ "09:40", "10:00" ]
        ]
      )
      expect(event.kalendarium_project.name).to eq("Tasks")
      expect(event.linked_db_row).to eq(row)
      expect(event.starts_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:00")
      expect(event.ends_at_utc.in_time_zone("UTC").strftime("%H:%M")).to eq("09:20")
    end
  end

  it "returns an error when no slot fits before the task deadline" do
    user, workspace, _database, row, date_created_property, due_date_property = build_stack(suffix: "deadline")

    travel_to Time.zone.parse("2026-04-12 17:50:00") do
      DbCell.create!(workspace: workspace, db_row: row, db_property: date_created_property, value_text: "2026-04-12")
      DbCell.create!(workspace: workspace, db_row: row, db_property: due_date_property, value_text: "2026-04-12")

      result = described_class.new(workspace: workspace, row: row, actor: user).call

      expect(result).not_to be_success
      expect(result.error).to eq("No open 20-minute slot is available before this task's deadline.")
    end
  end
end
