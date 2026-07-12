require "rails_helper"

RSpec.describe Databases::TimesheetTemplateService do
  it "loads only running timer candidates instead of every historical row and cell" do
    user = User.create!(email: "timesheet-active-timer@example.com", password: "password123")
    workspace = Workspace.create!(name: "Timesheet active timer", slug: "timesheet-active-timer")
    database = Database.create!(
      workspace:,
      created_by: user,
      name: "Time sheets",
      applied_template_name: described_class::TEMPLATE_NAME
    )
    started_property = DbProperty.create!(
      workspace:,
      database:,
      name: described_class::STARTED_AT_PROPERTY,
      property_type: :text
    )
    stopped_property = DbProperty.create!(
      workspace:,
      database:,
      name: described_class::STOPPED_AT_PROPERTY,
      property_type: :text
    )

    6.times do |index|
      row = DbRow.create!(workspace:, database:, title: "Completed #{index}")
      DbCell.create!(workspace:, db_row: row, db_property: started_property, value_text: "2026-07-11 08:00")
      DbCell.create!(workspace:, db_row: row, db_property: stopped_property, value_text: "2026-07-11 08:30")
    end

    running_row = DbRow.create!(workspace:, database:, title: "Running client work")
    DbCell.create!(workspace:, db_row: running_row, db_property: started_property, value_text: "2026-07-11 09:15")
    DbCell.create!(workspace:, db_row: running_row, db_property: stopped_property, value_text: "")

    instantiated = Hash.new(0)
    result = ActiveSupport::Notifications.subscribed(
      ->(_name, _start, _finish, _id, payload) { instantiated[payload[:class_name]] += payload[:record_count].to_i },
      "instantiation.active_record"
    ) do
      described_class.active_timer(workspace:)
    end

    expect(result).to include(database:, row: running_row)
    expect(result[:started_at]).to eq(Time.zone.parse("2026-07-11 09:15"))
    expect(instantiated["DbRow"]).to eq(1)
    expect(instantiated["DbCell"]).to eq(0)
  end

  it "continues treating a whitespace-only stopped value as an active timer" do
    user = User.create!(email: "timesheet-whitespace-timer@example.com", password: "password123")
    workspace = Workspace.create!(name: "Timesheet whitespace timer", slug: "timesheet-whitespace-timer")
    database = Database.create!(
      workspace:,
      created_by: user,
      name: "Time sheets",
      applied_template_name: described_class::TEMPLATE_NAME
    )
    started_property = DbProperty.create!(
      workspace:,
      database:,
      name: described_class::STARTED_AT_PROPERTY,
      property_type: :text
    )
    stopped_property = DbProperty.create!(
      workspace:,
      database:,
      name: described_class::STOPPED_AT_PROPERTY,
      property_type: :text
    )
    running_row = DbRow.create!(workspace:, database:, title: "Whitespace still running")
    DbCell.create!(workspace:, db_row: running_row, db_property: started_property, value_text: "2026-07-11 09:15")
    DbCell.create!(workspace:, db_row: running_row, db_property: stopped_property, value_text: "   ")

    result = described_class.active_timer(workspace:)

    expect(result).to include(database:, row: running_row)
  end
end
