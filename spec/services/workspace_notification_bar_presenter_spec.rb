require "rails_helper"

RSpec.describe WorkspaceNotificationBarPresenter do
  include ActiveSupport::Testing::TimeHelpers

  before do
    travel_to Time.zone.parse("2026-04-11 10:00:00")
  end

  after do
    travel_back
  end

  it "surfaces the clock, live calendar alert, unread mail, and unread updates" do
    user = User.create!(email: "notification-bar@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Status workspace", slug: "status-workspace", shell_status_bar_mode: "all")

    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Team",
      color_hex: "#2563eb",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Stand-up",
      starts_at_utc: 10.minutes.from_now,
      ends_at_utc: 40.minutes.from_now
    )

    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "gmail",
      label: "Inbox",
      access_token: "token"
    )
    EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-1",
      mailbox: "inbox",
      unread: true,
      subject: "New message",
      received_at: 2.minutes.ago
    )

    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.render?).to be(true)
    expect(presenter.show_clock?).to be(true)
    expect(presenter.show_alerts?).to be(true)
    expect(presenter.initial_clock_label).to include("Sat 11 Apr")
    expect(presenter.event_alert&.title).to eq("Stand-up")
    expect(presenter.event_timing_label).to eq("Starts in 10 min")
    expect(presenter.unread_email_count).to eq(1)
    expect(presenter.unread_update_count).to eq(1)
    expect(presenter.has_alerts?).to be(true)
  end

  it "respects time-only and off modes" do
    user = User.create!(email: "notification-bar-modes@example.com", password: "password123")
    time_only_workspace = Workspace.create!(name: "Clock only", slug: "clock-only", shell_status_bar_mode: "time_only")
    off_workspace = Workspace.create!(name: "Bar off", slug: "bar-off", shell_status_bar_mode: "off")

    time_only_presenter = described_class.new(workspace: time_only_workspace, user: user, reference_time: Time.zone.now)
    off_presenter = described_class.new(workspace: off_workspace, user: user, reference_time: Time.zone.now)

    expect(time_only_presenter.render?).to be(true)
    expect(time_only_presenter.show_clock?).to be(true)
    expect(time_only_presenter.show_alerts?).to be(false)
    expect(off_presenter.render?).to be(false)
  end
end
