require "rails_helper"

RSpec.describe Search::KnowledgeSuggestionService do
  it "returns cited suggestions with provenance-backed sources" do
    user = User.create!(email: "knowledge-suggest@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge suggest", slug: "knowledge-suggest")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Launch brief")
    chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Alex will send the launch brief to Errol for review.",
      token_count: 10,
      content_hash: "chunk-hash-1",
      source_content_hash: "source-hash-1",
      source_uri: "/w/#{workspace.slug}/pages/#{page.id}",
      source_title: page.title,
      metadata_json: { "entities" => { "names" => [ "Alex", "Errol" ] } }
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: {
          summary: "Recent work centers on the launch brief. [1]",
          insights: [ "Alex is the current owner of the brief. [1]" ],
          task_suggestions: [
            {
              title: "Follow up on launch brief review",
              owner: "Alex",
              rationale: "The brief still needs review from Errol. [1]",
              citation_indices: [ 1 ]
            }
          ],
          related_notes: [
            {
              title: "Launch brief",
              reason: "This note contains the current review handoff. [1]",
              citation_indices: [ 1 ]
            }
          ]
        }.to_json,
        usage: { prompt_tokens: 24, completion_tokens: 18, total_tokens: 42 }
      }
    )

    response = described_class.new(user: user, workspace: workspace).call

    expect(response.summary).to include("[1]")
    expect(response.insights.first).to include("[1]")
    expect(response.task_suggestions.first.fetch("owner")).to eq("Alex")
    expect(response.sources.first[:source_uri]).to eq(chunk.source_uri)
    expect(response.sources.first[:source_content_hash]).to eq("source-hash-1")
    expect(AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION)).to exist
  end
end
