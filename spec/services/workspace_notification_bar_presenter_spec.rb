require "rails_helper"

RSpec.describe WorkspaceNotificationBarPresenter do
  include ActiveSupport::Testing::TimeHelpers

  before do
    travel_to Time.zone.parse("2026-04-11 10:00:00")
  end

  after do
    travel_back
  end

  it "surfaces the clock, live calendar alert, and recent activity alerts without counting stale unread items" do
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
    EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-old",
      mailbox: "inbox",
      unread: true,
      subject: "Old unread message",
      received_at: 3.days.ago
    )

    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )
    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_MENTION,
      metadata: {},
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.render?).to be(true)
    expect(presenter.show_clock?).to be(true)
    expect(presenter.show_alerts?).to be(true)
    expect(presenter.initial_clock_label).to include("Sat 11 Apr")
    expect(presenter.event_alert&.title).to eq("Stand-up")
    expect(presenter.event_timing_label).to eq("Starts in 10 min")
    expect(presenter.recent_email_count).to eq(1)
    expect(presenter.recent_email_headline).to eq("1 email just came in")
    expect(presenter.recent_email_detail).to include("New message")
    expect(presenter.recent_update_count).to eq(1)
    expect(presenter.recent_update_headline).to eq("1 new workspace update")
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

  it "does not render for alerts-only mode when nothing recent has arrived" do
    user = User.create!(email: "notification-bar-empty@example.com", password: "password123")
    workspace = Workspace.create!(name: "Alerts only", slug: "alerts-only", shell_status_bar_mode: "alerts_only")

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.render?).to be(false)
  end
end
