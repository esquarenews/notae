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

  it "schedules missing chunk embeddings for async backfill" do
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
    expect(Search::BackfillChunkEmbeddingsJob).to receive(:perform_later)
      .with(user.id, workspace.id, [ chunk.id ])

    described_class.new(user: user, workspace: workspace, query: "roadmap").call

    expect(chunk.reload.embedding).to eq([])
    expect(chunk.embedding_model).to be_nil
  end

  it "continues semantic search when embedding backfill enqueue is unavailable" do
    user = User.create!(email: "semantic-backfill-queue-down@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Semantic Queue Down", slug: "semantic-queue-down")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Queue fallback page")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "queue fallback result",
      token_count: 3,
      content_hash: "hash-queue",
      embedding: [ 1.0, 0.0 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 1,
      text: "needs embedding",
      token_count: 2,
      content_hash: "hash-missing",
      embedding: [],
      embedding_model: nil
    )

    allow(Openai::EmbeddingsClient).to receive(:embed_with_usage).and_return(
      { embedding: [ 1.0, 0.0 ], usage: { prompt_tokens: 5, completion_tokens: 0, total_tokens: 5 } }
    )
    allow(Search::BackfillChunkEmbeddingsJob).to receive(:perform_later)
      .and_raise(Errno::ECONNREFUSED.new("Connection refused"))

    expect do
      results = described_class.new(user: user, workspace: workspace, query: "queue").call
      expect(results.map(&:title)).to include("Queue fallback page")
    end.not_to raise_error
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

  it "reranks exact title matches above weaker lexical matches" do
    user = User.create!(email: "semantic-rerank@example.com", password: "password123")
    workspace = Workspace.create!(name: "Semantic Rerank", slug: "semantic-rerank")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    strong_page = Page.create!(workspace: workspace, created_by: user, title: "Mac")
    weaker_page = Page.create!(workspace: workspace, created_by: user, title: "General Notes")
    Block.create!(
      workspace: workspace,
      page: weaker_page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "mac appears in body text once" } ] } ]
      }
    )

    results = described_class.new(user: user, workspace: workspace, query: "mac").call

    expect(results.first.title).to eq(strong_page.title)
  end
end
