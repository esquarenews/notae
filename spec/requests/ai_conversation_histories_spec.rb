require "rails_helper"

RSpec.describe "AI conversation histories", type: :request do
  it "shows only the last week's conversations in the center pane" do
    user = User.create!(email: "ai-history@example.com", password: "password123")
    workspace = Workspace.create!(name: "History Workspace", slug: "history-workspace")
    secondary_workspace = Workspace.create!(name: "Secondary Workspace", slug: "secondary-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: secondary_workspace, user: user, role: :owner)

    recent_conversation = AiConversation.create!(
      user: user,
      workspace: workspace,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_SUCCESS,
      prompt: "Is Mac mentioned?",
      answer: "Yes, Mac appears in this workspace.",
      created_at: 2.days.ago
    )
    cross_workspace_conversation = AiConversation.create!(
      user: user,
      workspace: secondary_workspace,
      scope: Search::AssistantQueryService::SCOPE_ACCOUNT,
      status: AiConversation::STATUS_SUCCESS,
      prompt: "Summarise all pages",
      answer: "Summary across account.",
      created_at: 12.hours.ago
    )
    AiConversation.create!(
      user: user,
      workspace: workspace,
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      status: AiConversation::STATUS_NOTICE,
      prompt: "Old prompt",
      answer: "Old answer",
      created_at: 8.days.ago
    )

    sign_in user
    get workspace_ai_conversation_history_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("AI Conversation History")
    expect(response.body).to include(recent_conversation.prompt)
    expect(response.body).to include(cross_workspace_conversation.prompt)
    expect(response.body).to include("History Workspace")
    expect(response.body).to include("Secondary Workspace")
    expect(response.body).to include("Copy result")
    expect(response.body).to include("data-copy-text-value=")
    expect(response.body).not_to include("Old prompt")
  end
end
