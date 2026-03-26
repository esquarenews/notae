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
    expect(payload[:url]).to eq("/w/#{workspace.slug}/agent-actions/#{agent_action.id}")
  end

  it "builds a knowledge suggestion payload that deep-links to the workspace home card" do
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
    expect(payload[:url]).to eq("/w/#{workspace.slug}?show_home=1#knowledge-suggestion-#{suggestion.id}")
  end
end
