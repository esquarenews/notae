require "rails_helper"

RSpec.describe KnowledgeSuggestion, type: :model do
  def build_suggestion(workspace:, user:, ai_conversation: nil, title: "Follow up")
    described_class.create!(
      workspace: workspace,
      user: user,
      ai_conversation: ai_conversation,
      kind: described_class::KIND_PROACTIVE,
      status: described_class::STATUS_ACTIVE,
      title: title,
      summary: "Check the dependency cleanup path.",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 6.hours.from_now
    )
  end

  it "is destroyed when its workspace is destroyed" do
    user = User.create!(email: "knowledge-workspace-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge workspace", slug: "knowledge-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    build_suggestion(workspace: workspace, user: user)

    expect { workspace.destroy! }.to change(described_class, :count).by(-1)
  end

  it "is destroyed when its user is destroyed" do
    user = User.create!(email: "knowledge-user-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge user workspace", slug: "knowledge-user-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    build_suggestion(workspace: workspace, user: user)

    expect { user.destroy! }.to change(described_class, :count).by(-1)
  end

  it "nullifies the ai conversation when the conversation is destroyed" do
    user = User.create!(email: "knowledge-conversation-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Knowledge conversation workspace", slug: "knowledge-conversation-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    ai_conversation = AiConversation.create!(
      user: user,
      workspace: workspace,
      scope: "workspace",
      status: AiConversation::STATUS_SUGGESTION,
      prompt: "What changed?",
      answer: "A new suggestion is available."
    )
    suggestion = build_suggestion(workspace: workspace, user: user, ai_conversation: ai_conversation)

    expect { ai_conversation.destroy! }
      .to change { suggestion.reload.ai_conversation_id }
      .from(ai_conversation.id)
      .to(nil)
  end
end
