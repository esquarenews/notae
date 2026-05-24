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
    expect(presenter.calendar_widget_date).to eq("2026-04-11")
    expect(presenter.event_alert&.title).to eq("Stand-up")
    expect(presenter.event_timing_label).to eq("Starts in 10 min")
    expect(presenter.recent_email_count).to eq(1)
    expect(presenter.recent_email_headline).to eq("1 email just came in")
    expect(presenter.recent_email_detail).to include("New message")
    expect(presenter.recent_update_count).to eq(1)
    expect(presenter.recent_update_headline).to eq("1 new workspace update")
    expect(presenter.has_alerts?).to be(true)
  end

  it "surfaces an active time sheet timer for the shell calendar pop-up" do
    user = User.create!(email: "notification-bar-timesheet@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Timesheet status workspace", slug: "timesheet-status-workspace", shell_status_bar_mode: "all")
    database = Database.create!(workspace: workspace, created_by: user, name: "Time sheets", applied_template_name: "Time sheets")
    started_property = DbProperty.create!(workspace: workspace, database: database, name: "Date/time clock started", property_type: :text)
    stopped_property = DbProperty.create!(workspace: workspace, database: database, name: "Date/time clock stopped", property_type: :text)
    row = DbRow.create!(workspace: workspace, database: database, title: "Client support")
    DbCell.create!(workspace: workspace, db_row: row, db_property: started_property, value_text: "2026-04-11 09:15")
    DbCell.create!(workspace: workspace, db_row: row, db_property: stopped_property, value_text: "")

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.parse("2026-04-11 10:00:00"))

    expect(presenter.active_timesheet_timer).to include(
      label: "Client support",
      started_at: "2026-04-11T19:15",
      elapsed_label: "00:45:00"
    )
  end

  it "routes alert-grade AI notifications into the shell widget separately from generic updates" do
    user = User.create!(email: "notification-bar-ai@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "AI status workspace", slug: "ai-status-workspace", shell_status_bar_mode: "all")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Review the launch note",
      summary: "A new AI suggestion is ready. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: 5.minutes.ago,
      expires_at: 6.hours.from_now
    )
    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {}
    )
    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.recent_ai_update_count).to eq(1)
    expect(presenter.recent_ai_update_present?).to be(true)
    expect(presenter.recent_ai_update_headline).to eq("New AI suggestion")
    expect(presenter.recent_ai_update_detail).to include("Review the launch note")
    expect(presenter.recent_ai_update_path).to eq("/w/#{workspace.slug}?show_home=1#knowledge-suggestion-#{suggestion.id}")
    expect(presenter.recent_update_count).to eq(1)
    expect(presenter.recent_update_headline).to eq("1 new workspace update")
  end

  it "surfaces codex completions as a dedicated AI alert with the codex title" do
    user = User.create!(email: "notification-bar-codex@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Codex status workspace", slug: "codex-status-workspace", shell_status_bar_mode: "all")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Grid cleanup ready",
        "body" => "The layout pass is ready for review.",
        "path" => "/w/#{workspace.slug}/library"
      }
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.recent_ai_update_count).to eq(1)
    expect(presenter.recent_ai_update_present?).to be(true)
    expect(presenter.recent_ai_update_kind_label).to eq("Codex")
    expect(presenter.recent_ai_update_headline).to eq("codex: Grid cleanup ready")
    expect(presenter.recent_ai_update_detail).to eq("The layout pass is ready for review.")
    expect(presenter.recent_ai_update_path).to eq("/w/#{workspace.slug}/library")
    expect(presenter.recent_update_count).to eq(0)
  end

  it "surfaces the daily summary agenda in the shell widget detail" do
    user = User.create!(email: "notification-bar-daily@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Daily AI status workspace", slug: "daily-ai-status-workspace", shell_status_bar_mode: "all")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily morning summary",
      summary: "Today has two meetings. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_for_date: Date.new(2026, 4, 11),
      generated_at: 5.minutes.ago
    )
    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {
        "daily_agenda_items" => [
          { "time" => "09:00", "title" => "Stand-up" },
          { "time" => "11:30", "title" => "Client review" }
        ],
        "daily_agenda_total_count" => 2
      }
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.recent_ai_update_headline).to eq("Daily workspace brief ready")
    expect(presenter.recent_ai_update_detail).to include("09:00 — Stand-up")
    expect(presenter.recent_ai_update_detail).to include("11:30 — Client review")
  end

  it "uses explicit push wording for test notifications in the shell widget" do
    user = User.create!(email: "notification-bar-test-push@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Push status workspace", slug: "push-status-workspace", shell_status_bar_mode: "all")

    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_TEST_PUSH,
      metadata: {
        "title" => "Notae test notification",
        "body" => "Push notifications are working on this device for Push status workspace."
      }
    )

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.recent_update_count).to eq(1)
    expect(presenter.recent_update_kind_label).to eq("Push")
    expect(presenter.recent_update_headline).to eq("Notae test notification")
    expect(presenter.recent_update_detail).to eq("Push notifications are working on this device for Push status workspace.")
  end

  it "respects time-only and off modes" do
    user = User.create!(email: "notification-bar-modes@example.com", password: "password123")
    time_only_workspace = Workspace.create!(name: "Clock only", slug: "clock-only", shell_status_bar_mode: "time_only")
    off_workspace = Workspace.create!(name: "Bar off", slug: "bar-off", shell_status_bar_mode: "off")

    time_only_presenter = described_class.new(workspace: time_only_workspace, user: user, reference_time: Time.zone.now)
    off_presenter = described_class.new(workspace: off_workspace, user: user, reference_time: Time.zone.now)

    expect(time_only_presenter.render?).to be(true)
    expect(time_only_presenter.shell_enabled?).to be(true)
    expect(time_only_presenter.show_clock?).to be(true)
    expect(time_only_presenter.show_alerts?).to be(false)
    expect(off_presenter.render?).to be(false)
    expect(off_presenter.shell_enabled?).to be(false)
  end

  it "does not render for alerts-only mode when nothing recent has arrived" do
    user = User.create!(email: "notification-bar-empty@example.com", password: "password123")
    workspace = Workspace.create!(name: "Alerts only", slug: "alerts-only", shell_status_bar_mode: "alerts_only")

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.render?).to be(false)
    expect(presenter.shell_enabled?).to be(true)
  end

  it "does not render for a workspace without a slug" do
    user = User.create!(email: "notification-bar-unsaved@example.com", password: "password123")
    workspace = Workspace.new(name: "Draft workspace")

    presenter = described_class.new(workspace: workspace, user: user, reference_time: Time.zone.now)

    expect(presenter.render?).to be(false)
    expect(presenter.shell_enabled?).to be(false)
  end
end
