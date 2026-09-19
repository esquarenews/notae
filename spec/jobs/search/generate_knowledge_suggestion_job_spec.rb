require "rails_helper"

RSpec.describe Search::GenerateKnowledgeSuggestionJob, type: :job do
  it "runs suggestion generation and clears the pending tracker" do
    user = User.create!(email: "knowledge-job@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge job", slug: "knowledge-job")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    Search::KnowledgeSuggestionGenerationTracker.mark_pending!(
      user: user,
      workspace: workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE
    )

    service = instance_double(Search::PersistKnowledgeSuggestionService, call: nil)
    allow(Search::PersistKnowledgeSuggestionService).to receive(:new).and_return(service)

    described_class.perform_now(user.id, workspace.id, KnowledgeSuggestion::KIND_PROACTIVE)

    expect(Search::PersistKnowledgeSuggestionService).to have_received(:new).with(
      user: user,
      workspace: workspace,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      service_tier: "flex"
    )
    expect(service).to have_received(:call)
    expect(
      Search::KnowledgeSuggestionGenerationTracker.pending?(
        user: user,
        workspace: workspace,
        kind: KnowledgeSuggestion::KIND_PROACTIVE
      )
    ).to eq(false)
  end
end
