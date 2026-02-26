require "rails_helper"

RSpec.describe "Assistant query evaluation set" do
  it "passes search-check and summary evaluation prompts with citations" do
    user = User.create!(email: "assistant-eval@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Eval", slug: "assistant-eval")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Evaluation Document")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Mac appears in scope notes. Key tasks include launch, docs, and QA.",
      token_count: 12,
      content_hash: "assistant-eval-1",
      embedding: [ 0.8, 0.1 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    cases = [
      {
        prompt: "Is Mac mentioned in this workspace?",
        llm_text: "Yes, Mac is mentioned [1].",
        expects: ->(response) { expect(response.answer.downcase).to include("yes"); expect(response.answer).to include("[1]") }
      },
      {
        prompt: "Summarise this into bullet points.",
        llm_text: "- Launch prep [1]\n- QA and docs [1]",
        expects: ->(response) { expect(response.answer).to include("Launch prep"); expect(response.answer).to include("[1]") }
      }
    ]

    cases.each do |evaluation_case|
      allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
        {
          text: evaluation_case[:llm_text],
          usage: { prompt_tokens: 100, completion_tokens: 20, total_tokens: 120 }
        }
      )

      response = Search::AssistantQueryService.new(
        user: user,
        workspace: workspace,
        prompt: evaluation_case[:prompt],
        scope: Search::AssistantQueryService::SCOPE_WORKSPACE
      ).call

      expect(response).to be_present
      evaluation_case[:expects].call(response)
      expect(response.sources).not_to be_empty
    end
  end
end
