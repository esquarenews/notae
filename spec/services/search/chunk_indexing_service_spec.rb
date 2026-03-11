require "rails_helper"

RSpec.describe Search::ChunkIndexingService do
  it "indexes page content into chunks" do
    user = User.create!(email: "chunk-page@example.com", password: "password123")
    workspace = Workspace.create!(name: "Chunk Page", slug: "chunk-page")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Indexable Page")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "alpha beta gamma delta" } ] } ]
      }
    )

    described_class.index_page!(page: page)

    chunks = SearchChunk.for_source(SearchChunk::SOURCE_PAGE, page.id).order(:chunk_index)
    expect(chunks).to be_present
    expect(chunks.first.workspace_id).to eq(workspace.id)
    expect(chunks.first.page_id).to eq(page.id)
    expect(chunks.first.text).to include("Indexable Page")
  end

  it "clears stored embeddings when source text changes" do
    user = User.create!(email: "chunk-reset@example.com", password: "password123")
    workspace = Workspace.create!(name: "Chunk Reset", slug: "chunk-reset")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Reset Page")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "initial copy" } ] } ]
      }
    )

    described_class.index_page!(page: page)
    chunk = SearchChunk.for_source(SearchChunk::SOURCE_PAGE, page.id).first
    chunk.update!(embedding: [ 0.1, 0.2, 0.3 ], embedding_model: "text-embedding-3-small")

    block.update!(
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "changed copy" } ] } ]
      }
    )
    described_class.index_page!(page: page)

    expect(chunk.reload.embedding).to eq([])
    expect(chunk.embedding_model).to be_nil
  end

  it "removes chunks for archived pages" do
    user = User.create!(email: "chunk-archive@example.com", password: "password123")
    workspace = Workspace.create!(name: "Chunk Archive", slug: "chunk-archive")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Archive Page")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "archive me" } ] } ]
      }
    )

    described_class.index_page!(page: page)
    expect(SearchChunk.for_source(SearchChunk::SOURCE_PAGE, page.id)).to exist

    page.archive!
    described_class.index_page!(page: page)

    expect(SearchChunk.for_source(SearchChunk::SOURCE_PAGE, page.id)).to be_empty
  end

  it "indexes database row text into chunks" do
    user = User.create!(email: "chunk-row@example.com", password: "password123")
    workspace = Workspace.create!(name: "Chunk Row", slug: "chunk-row")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    database = Database.create!(workspace: workspace, name: "Tasks")
    row = DbRow.create!(workspace: workspace, database: database, title: "Alpha row", data_json: { notes: "launch milestone" })

    described_class.index_db_row!(db_row: row)

    chunk = SearchChunk.for_source(SearchChunk::SOURCE_DB_ROW, row.id).first
    expect(chunk).to be_present
    expect(chunk.db_row_id).to eq(row.id)
    expect(chunk.database_id).to eq(database.id)
    expect(chunk.text).to include("Alpha row")
  end

  it "indexes meeting transcripts with provenance metadata" do
    user = User.create!(email: "chunk-meeting@example.com", password: "password123")
    workspace = Workspace.create!(name: "Chunk Meeting", slug: "chunk-meeting")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    session = MeetingSession.create!(
      workspace: workspace,
      created_by: user,
      updated_by: user,
      title: "Weekly standup",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      transcript_text: "[00:00] Errol: Review the launch checklist.",
      summary_markdown: "### Summary\n- Review launch checklist."
    )

    described_class.index_meeting_session!(meeting_session: session)

    chunk = SearchChunk.for_source(SearchChunk::SOURCE_MEETING_SESSION, session.id).first
    expect(chunk).to be_present
    expect(chunk.meeting_session_id).to eq(session.id)
    expect(chunk.source_uri).to eq("/w/#{workspace.slug}/meetings#meeting_session_#{session.id}")
    expect(chunk.source_title).to eq("Weekly standup")
    expect(chunk.metadata_json.dig("entities", "names")).to include("Errol")
    expect(chunk.hash_verification_succeeds?).to eq(true)
  end
end
