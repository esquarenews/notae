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

  it "routes codex completion notifications with workspace-home destinations to notification details" do
    workspace = Workspace.create!(name: "Resolver Codex Home Path", slug: "resolver-codex-home-path")
    user = User.create!(email: "resolver-codex-home-path@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "I've prepared fresh suggestions",
        "body" => "I've prepared fresh suggestions regarding Bela App.",
        "path" => "/w/#{workspace.slug}"
      }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq(Rails.application.routes.url_helpers.workspace_notification_path(workspace_slug: workspace.slug, id: notification.id))
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

    expect(destination).to eq(Rails.application.routes.url_helpers.workspace_notification_path(workspace_slug: workspace.slug, id: notification.id))
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

  it "routes knowledge suggestion notifications to the concrete suggestion page" do
    workspace = Workspace.create!(name: "Resolver Suggestion", slug: "resolver-suggestion")
    user = User.create!(email: "resolver-suggestion@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    conversation = AiConversation.create!(
      workspace: workspace,
      user: user,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUGGESTION,
      prompt: "Proactive workspace suggestion",
      answer: "The clicked suggestion should open the full generated detail. [1]"
    )
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      ai_conversation: conversation,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Review stalled task",
      summary: "The clicked suggestion should render directly. [1]",
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

    destination = described_class.new(notification: notification).call

    expect(destination).to eq(Rails.application.routes.url_helpers.knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id, anchor: "knowledge-suggestion-#{suggestion.id}"))
  end

  it "routes metadata-only knowledge suggestion notifications to the concrete suggestion page" do
    workspace = Workspace.create!(name: "Resolver Suggestion Fallback", slug: "resolver-suggestion-fallback")
    user = User.create!(email: "resolver-suggestion-fallback@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Review stalled task",
      summary: "The clicked suggestion should render directly. [1]",
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
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: { "knowledge_suggestion_id" => suggestion.id }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq(Rails.application.routes.url_helpers.knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id, anchor: "knowledge-suggestion-#{suggestion.id}"))
  end

  it "does not resolve metadata-only knowledge suggestion notifications across users" do
    workspace = Workspace.create!(name: "Resolver Suggestion Isolation", slug: "resolver-suggestion-isolation")
    actor = User.create!(email: "resolver-suggestion-isolation-actor@example.com", password: "password123")
    recipient = User.create!(email: "resolver-suggestion-isolation-recipient@example.com", password: "password123")
    other_user = User.create!(email: "resolver-suggestion-isolation-other@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: recipient, role: :owner)
    Membership.create!(workspace: workspace, user: other_user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: other_user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Private suggestion",
      summary: "This belongs to another user. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )
    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
      metadata: { "knowledge_suggestion_id" => suggestion.id }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq("/w/#{workspace.slug}/notifications")
  end

  it "rescues legacy codex-style suggestion notifications with stored suggestion metadata" do
    workspace = Workspace.create!(name: "Resolver Suggestion Legacy", slug: "resolver-suggestion-legacy")
    user = User.create!(email: "resolver-suggestion-legacy@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Legacy proactive suggestion",
      summary: "This should not fall back to workspace home. [1]",
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
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "I've prepared fresh suggestions",
        "path" => "/w/#{workspace.slug}",
        "knowledge_suggestion_id" => suggestion.id
      }
    )

    destination = described_class.new(notification: notification).call

    expect(destination).to eq(Rails.application.routes.url_helpers.knowledge_suggestion_path(workspace_slug: workspace.slug, id: suggestion.id, anchor: "knowledge-suggestion-#{suggestion.id}"))
  end
end
