require "rails_helper"

RSpec.describe Search::KnowledgeSuggestionNotificationService do
  it "stores the day's agenda on daily summary notifications" do
    user = User.create!(email: "knowledge-notification@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Knowledge notification", slug: "knowledge-notification")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Primary",
      color_hex: "#2563eb",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )
    melbourne = ActiveSupport::TimeZone["Australia/Melbourne"]
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Stand-up",
      starts_at_utc: melbourne.parse("2026-04-17 09:00").utc,
      ends_at_utc: melbourne.parse("2026-04-17 09:30").utc
    )
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily morning summary",
      summary: "Today is focused on delivery. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_for_date: Date.new(2026, 4, 17),
      generated_at: Time.current
    )

    described_class.new(suggestion: suggestion, actor: user).notify_ready!

    notification = Notification.where(
      workspace: workspace,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
    ).last

    expect(notification).to be_present
    expect(notification.metadata).to include(
      "kind" => KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      "daily_agenda_date" => "2026-04-17",
      "daily_agenda_total_count" => 1,
      "daily_agenda_empty" => false
    )
    expect(notification.metadata.fetch("daily_agenda_items")).to include(
      a_hash_including("time" => "09:00", "title" => "Stand-up")
    )
  end
end
