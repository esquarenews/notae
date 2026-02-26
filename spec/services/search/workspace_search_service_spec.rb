require "rails_helper"

RSpec.describe Search::WorkspaceSearchService do
  it "includes semantic chunk matches for accessible pages" do
    user = User.create!(email: "semantic-search@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Semantic Workspace", slug: "semantic-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Launch Plan")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "launch sequence critical path timeline",
      token_count: 5,
      content_hash: "hash-1",
      embedding: [ 1.0, 0.0, 0.0 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::EmbeddingsClient).to receive(:embed_with_usage).and_return(
      { embedding: [ 1.0, 0.0, 0.0 ], usage: { prompt_tokens: 12, completion_tokens: 0, total_tokens: 12 } }
    )

    results = described_class.new(user: user, workspace: workspace, query: "launch schedule").call

    expect(results.map(&:title)).to include("Launch Plan")
    expect(results.map(&:kind)).to include("Page")
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_SEMANTIC_QUERY)
    expect(usage).to exist
  end

  it "backfills missing chunk embeddings before semantic ranking" do
    user = User.create!(email: "semantic-backfill@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Semantic Backfill", slug: "semantic-backfill")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Roadmap")
    chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "roadmap planning objectives",
      token_count: 3,
      content_hash: "hash-2",
      embedding: [],
      embedding_model: nil
    )

    allow(Openai::EmbeddingsClient).to receive(:embed_with_usage).and_return(
      { embedding: [ 1.0, 0.0 ], usage: { prompt_tokens: 8, completion_tokens: 0, total_tokens: 8 } }
    )
    allow(Openai::EmbeddingsClient).to receive(:embed_many_with_usage).and_return(
      { embeddings: [ [ 1.0, 0.0 ] ], usage: { prompt_tokens: 14, completion_tokens: 0, total_tokens: 14 } }
    )

    described_class.new(user: user, workspace: workspace, query: "roadmap").call

    expect(chunk.reload.embedding).to eq([ 1.0, 0.0 ])
    expect(chunk.embedding_model).to eq(SearchChunk::EMBEDDING_MODEL)
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_SEMANTIC_BACKFILL)
    expect(usage).to exist
  end

  it "skips semantic lookup when OpenAI key is not configured" do
    user = User.create!(email: "semantic-no-key@example.com", password: "password123", openai_api_key: nil)
    workspace = Workspace.create!(name: "Semantic No Key", slug: "semantic-no-key")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Openai::EmbeddingsClient).not_to receive(:embed_with_usage)
    expect(Openai::EmbeddingsClient).not_to receive(:embed_many_with_usage)

    described_class.new(user: user, workspace: workspace, query: "anything").call
  end

  it "skips semantic lookup when guardrails block AI search" do
    user = User.create!(email: "semantic-guardrail@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Semantic Guardrail", slug: "semantic-guardrail")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Search::AiRateLimiter).to receive(:allowed?)
      .with(user: user, workspace: workspace, operation: "semantic_search")
      .and_return(false)
    expect(Openai::EmbeddingsClient).not_to receive(:embed_with_usage)

    results = described_class.new(user: user, workspace: workspace, query: "anything").call
    expect(results).to eq([])
  end
end
