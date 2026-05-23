require "rails_helper"

RSpec.describe Notifications::DestinationResolver do
  it "resolves agent action notifications to the draft page" do
    workspace = Workspace.create!(name: "Resolver Agent", slug: "resolver-agent")
    actor = User.create!(email: "resolver-agent-actor@example.com", password: "password123")
    recipient = User.create!(email: "resolver-agent-recipient@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: actor, role: :owner)
    Membership.create!(workspace: workspace, user: recipient, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: actor,
      attributes: {
        title: "Ship the release note",
        proposed_by: "manual",
        target_system: "notae",
        draft_type: "nota_draft",
        payload_json: {
          "title" => "Ship the release note",
          "body" => "Summarize the release."
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

    destination = described_class.new(notification: notification).call

    expect(destination).to eq("/w/#{workspace.slug}/agent-actions/#{agent_action.id}")
  end

  it "falls back to workspace notifications when the notifiable target is gone" do
    workspace = Workspace.create!(name: "Resolver Fallback", slug: "resolver-fallback")
    actor = User.create!(email: "resolver-fallback-actor@example.com", password: "password123")
    recipient = User.create!(email: "resolver-fallback-recipient@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: actor, role: :owner)
    Membership.create!(workspace: workspace, user: recipient, role: :owner)

    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
      metadata: {}
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq("/w/#{workspace.slug}/notifications")
  end

  it "uses the stored internal path for codex completion notifications" do
    workspace = Workspace.create!(name: "Resolver Codex", slug: "resolver-codex")
    user = User.create!(email: "resolver-codex@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Codex request completed",
        "path" => "/w/#{workspace.slug}/library"
      }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq("/w/#{workspace.slug}/library")
  end

  it "falls back when a codex completion notification stored a filesystem path" do
    workspace = Workspace.create!(name: "Resolver Codex Bad Path", slug: "resolver-codex-bad-path")
    user = User.create!(email: "resolver-codex-bad-path@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Codex request completed",
        "path" => "/Users/errolschmidt/Documents/tabulae"
      }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq("/w/#{workspace.slug}/notifications")
  end

  it "keeps codex completion paths with query strings and anchors when the route is valid" do
    workspace = Workspace.create!(name: "Resolver Codex Query", slug: "resolver-codex-query")
    user = User.create!(email: "resolver-codex-query@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    destination_path = "/w/#{workspace.slug}/kalendarium?view=week#today"

    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Codex request completed",
        "path" => destination_path
      }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq(destination_path)
  end
end
