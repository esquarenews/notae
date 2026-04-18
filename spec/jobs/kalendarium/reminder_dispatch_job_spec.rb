require "rails_helper"

RSpec.describe Kalendarium::ReminderDispatchJob do
  include ActiveJob::TestHelper

  it "uses the workspace email override when dispatching reminder emails" do
    owner = User.create!(
      email: "kalendarium-reminder-owner@example.com",
      password: "password123",
      email_notify_activity: false,
      email_notify_always_send: true
    )
    workspace = Workspace.create!(name: "Kalendarium Reminder Workspace", slug: "kalendarium-reminder-workspace")
    membership = Membership.create!(
      workspace: workspace,
      user: owner,
      role: :owner,
      notification_preferences_json: { "email_notify_activity" => true }
    )
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: owner,
      created_by: owner,
      provider: "google",
      label: "Personal Google",
      status: "connected",
      access_token: "token",
      refresh_token: "refresh-token"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: owner,
      name: "Personal",
      color_hex: "#3366FF",
      time_zone: "Australia/Melbourne",
      provider: "google",
      remote_id: "calendar-1",
      source_kind: "provider",
      enabled: true
    )
    now = Time.current.change(sec: 0)
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: owner,
      updated_by: owner,
      title: "Reminder Event",
      starts_at_utc: now + 60.seconds,
      ends_at_utc: now + 2.hours,
      status: "confirmed",
      visibility: "default",
      source_kind: "provider",
      reminder_offsets_minutes: [0],
      meeting_capture_enabled: false
    )

    clear_enqueued_jobs

    expect do
      described_class.perform_now(workspace.id)
    end.to have_enqueued_mail(NotificationMailer, :calendar_reminder_notification)

    notification = Notification.find_by!(
      workspace: workspace,
      recipient: owner,
      notification_type: Notification::TYPE_CALENDAR_REMINDER,
      notifiable: event
    )

    expect(notification.metadata["reminder_offset_minutes"]).to eq(0)
    expect(owner.email_notify_activity_for?(workspace, membership: membership)).to be(true)
  end
end
