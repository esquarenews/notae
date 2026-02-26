require "rails_helper"

RSpec.describe Search::BackfillChunkEmbeddingsJob, type: :job do
  it "fills missing embeddings and logs usage" do
    user = User.create!(email: "job-backfill@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Job Backfill", slug: "job-backfill")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Chunk source")
    chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "missing embedding chunk",
      token_count: 3,
      content_hash: "job-backfill-hash",
      embedding: [],
      embedding_model: nil
    )

    allow(Openai::EmbeddingsClient).to receive(:embed_many_with_usage).and_return(
      { embeddings: [ [ 0.1, 0.2 ] ], usage: { prompt_tokens: 11, completion_tokens: 0, total_tokens: 11 } }
    )

    described_class.perform_now(user.id, workspace.id, [ chunk.id ])

    expect(chunk.reload.embedding).to eq([ 0.1, 0.2 ])
    expect(chunk.embedding_model).to eq(SearchChunk::EMBEDDING_MODEL)
    expect(AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_SEMANTIC_BACKFILL)).to exist
  end
end
