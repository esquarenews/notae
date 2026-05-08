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
    expect(response.headers["X-Notae-Perf-Action"]).to eq("WorkspaceNotificationBarsController#show")
    expect(response.headers["X-Notae-Perf-Sql-Queries"]).to be_present

    payload = JSON.parse(response.body)
    expect(payload.dig("data", "has_alerts")).to eq(true)
    expect(payload.dig("data", "html")).to include("Notae AI")
    expect(payload.dig("data", "html")).to include("New AI suggestion")
    expect(payload.dig("data", "html")).to include("Follow up with the design team")
    expect(payload.dig("data", "html")).to include(workspace_path(workspace.slug, show_home: 1, anchor: "knowledge-suggestion-#{suggestion.id}"))
  end

  it "renders codex completion cards in the AI alert stream" do
    user = User.create!(email: "workspace-bar-codex@example.com", password: "password123")
    workspace = Workspace.create!(name: "Workspace Bar Codex", slug: "workspace-bar-codex", shell_status_bar_mode: "all")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    Notification.create!(
      workspace: workspace,
      recipient: user,
      actor: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: {
        "title" => "Layout pass ready",
        "body" => "The shell polish is ready for review.",
        "path" => "/w/#{workspace.slug}/library"
      }
    )

    sign_in user
    get workspace_notification_bar_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Notae-Perf-Action"]).to eq("WorkspaceNotificationBarsController#show")

    payload = JSON.parse(response.body)
    expect(payload.dig("data", "has_alerts")).to eq(true)
    expect(payload.dig("data", "html")).to include("Codex")
    expect(payload.dig("data", "html")).to include("codex: Layout pass ready")
    expect(payload.dig("data", "html")).to include("The shell polish is ready for review.")
    expect(payload.dig("data", "html")).to include("/w/#{workspace.slug}/library")
  end
end
