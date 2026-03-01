require "rails_helper"

RSpec.describe Kalendarium::SyncCalendarJob, type: :job do
  def build_stack(suffix:)
    user = User.create!(email: "kal-sync-calendar-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Sync Calendar Job #{suffix}", slug: "kal-sync-calendar-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud sync",
      provider_username: "apple-id@example.com",
      provider_password: "aaaa-bbbb-cccc-dddd"
    )
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

    [ connection, calendar ]
  end

  it "forwards the specific calendar to the connection sync service" do
    connection, calendar = build_stack(suffix: "forward")
    sync_service = instance_double(Kalendarium::ConnectionSyncService, call: true)

    expect(Kalendarium::ConnectionSyncService).to receive(:new).with(connection: connection, calendar: calendar).and_return(sync_service)

    described_class.perform_now(calendar.id)
  end
end
