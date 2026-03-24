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
end
