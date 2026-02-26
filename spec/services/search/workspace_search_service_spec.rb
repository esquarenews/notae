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

    allow(Openai::EmbeddingsClient).to receive(:embed).and_return([ 1.0, 0.0, 0.0 ])

    results = described_class.new(user: user, workspace: workspace, query: "launch schedule").call

    expect(results.map(&:title)).to include("Launch Plan")
    expect(results.map(&:kind)).to include("Page")
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

    allow(Openai::EmbeddingsClient).to receive(:embed).and_return([ 1.0, 0.0 ])
    allow(Openai::EmbeddingsClient).to receive(:embed_many).and_return([ [ 1.0, 0.0 ] ])

    described_class.new(user: user, workspace: workspace, query: "roadmap").call

    expect(chunk.reload.embedding).to eq([ 1.0, 0.0 ])
    expect(chunk.embedding_model).to eq(SearchChunk::EMBEDDING_MODEL)
  end

  it "skips semantic lookup when OpenAI key is not configured" do
    user = User.create!(email: "semantic-no-key@example.com", password: "password123", openai_api_key: nil)
    workspace = Workspace.create!(name: "Semantic No Key", slug: "semantic-no-key")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Openai::EmbeddingsClient).not_to receive(:embed)
    expect(Openai::EmbeddingsClient).not_to receive(:embed_many)

    described_class.new(user: user, workspace: workspace, query: "anything").call
  end
end
