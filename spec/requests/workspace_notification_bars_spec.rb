require "rails_helper"

RSpec.describe "Workspace notification bar", type: :request do
  it "renders AI alert cards from the refresh endpoint for unread knowledge suggestions" do
    user = User.create!(email: "workspace-bar-refresh@example.com", password: "password123")
    workspace = Workspace.create!(name: "Workspace Bar", slug: "workspace-bar", shell_status_bar_mode: "all")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    suggestion = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Follow up with the design team",
      summary: "A new AI suggestion is ready. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: 3.minutes.ago,
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

    sign_in user
    get workspace_notification_bar_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)

    payload = JSON.parse(response.body)
    expect(payload.dig("data", "has_alerts")).to eq(true)
    expect(payload.dig("data", "html")).to include("Notae AI")
    expect(payload.dig("data", "html")).to include("New AI suggestion")
    expect(payload.dig("data", "html")).to include("Follow up with the design team")
    expect(payload.dig("data", "html")).to include(workspace_path(workspace.slug, show_home: 1, anchor: "knowledge-suggestion-#{suggestion.id}"))
  end
end
