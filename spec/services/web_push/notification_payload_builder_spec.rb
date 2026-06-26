require "rails_helper"

RSpec.describe WebPush::NotificationPayloadBuilder do
  it "builds an agent action payload that deep-links to the draft" do
    workspace = Workspace.create!(name: "Web Push Payload", slug: "web-push-payload")
    actor = User.create!(email: "web-push-payload-actor@example.com", password: "password123")
    recipient = User.create!(email: "web-push-payload-recipient@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: actor, role: :owner)
    Membership.create!(workspace: workspace, user: recipient, role: :owner)
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: actor,
      attributes: {
        title: "Create summary note",
        proposed_by: "manual",
        target_system: "notae",
        draft_type: "nota_draft",
        payload_json: {
          "title" => "Create summary note",
          "body" => "Summarize the call."
        }
      }
    ).call
    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notifiable: agent_action,
      notification_type: Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
      metadata: {}
    )

    payload = described_class.new(notification: notification).call

    expect(payload[:title]).to eq("Agent draft awaiting approval")
    expect(payload[:body]).to include("Create summary note")
    expect(payload[:url]).to eq("/app/notifications/#{notification.id}")
  end

  it "builds a knowledge suggestion payload that launches through the notification resolver" do
    workspace = Workspace.create!(name: "Knowledge Push", slug: "knowledge-push")
    user = User.create!(email: "knowledge-push@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Follow up with finance",
      summary: "A fresh invoice issue needs attention. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {}
    )

    payload = described_class.new(notification: notification).call

    expect(payload[:title]).to eq("New AI suggestion")
    expect(payload[:body]).to include("Follow up with finance")
    expect(payload[:url]).to eq("/app/notifications/#{notification.id}")
  end

  it "builds a daily summary payload with a clean event list" do
    workspace = Workspace.create!(name: "Daily summary push", slug: "daily-summary-push")
    user = User.create!(email: "daily-summary-push@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily morning summary",
      summary: "The day is focused on delivery. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_for_date: Date.new(2026, 4, 17),
      generated_at: Time.current
    )
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: {
        "daily_agenda_items" => [
          { "time" => "09:00", "title" => "Stand-up" },
          { "time" => "11:30", "title" => "Client review" },
          { "time" => "15:00", "title" => "Prep deck" }
        ],
        "daily_agenda_total_count" => 4
      }
    )

    payload = described_class.new(notification: notification).call

    expect(payload[:title]).to eq("Daily workspace brief ready")
    expect(payload[:body]).to include("09:00 — Stand-up")
    expect(payload[:body]).to include("11:30 — Client review")
    expect(payload[:body]).to include("15:00 — Prep deck")
    expect(payload[:body]).to include("+1 more today")
    expect(payload[:url]).to eq("/app/notifications/#{notification.id}")
  end

  it "builds a codex completion payload from notification metadata" do
    workspace = Workspace.create!(name: "Codex Push", slug: "codex-push")
    user = User.create!(email: "codex-push@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Codex request completed",
        "body" => "The grid cleanup is ready for review.",
        "path" => "/w/#{workspace.slug}/library"
      }
    )

    payload = described_class.new(notification: notification).call

    expect(payload[:title]).to eq("codex: request completed")
    expect(payload[:body]).to eq("The grid cleanup is ready for review.")
    expect(payload[:url]).to eq("/app/notifications/#{notification.id}")
    expect(payload[:type]).to eq(Notification::TYPE_CODEX_REQUEST_COMPLETED)
    expect(payload[:require_interaction]).to eq(true)
    expect(payload.keys).to contain_exactly(
      :notification_id,
      :type,
      :title,
      :body,
      :url,
      :tag,
      :icon,
      :badge,
      :require_interaction
    )
  end

  it "builds a test push payload from notification metadata" do
    workspace = Workspace.create!(name: "Test Push", slug: "test-push")
    user = User.create!(email: "test-push@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_TEST_PUSH,
      metadata: {
        "title" => "Notae test notification",
        "body" => "Push notifications are working on this device for Test Push.",
        "path" => "/w/#{workspace.slug}/settings/notifications"
      }
    )

    payload = described_class.new(notification: notification).call

    expect(payload[:title]).to eq("Notae test notification")
    expect(payload[:body]).to eq("Push notifications are working on this device for Test Push.")
    expect(payload[:url]).to eq("/app/notifications/#{notification.id}")
    expect(payload[:type]).to eq(Notification::TYPE_TEST_PUSH)
    expect(payload[:require_interaction]).to eq(true)
    expect(payload.keys).to contain_exactly(
      :notification_id,
      :type,
      :title,
      :body,
      :url,
      :tag,
      :icon,
      :badge,
      :require_interaction
    )
  end
end
