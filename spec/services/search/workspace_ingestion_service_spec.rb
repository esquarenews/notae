require "rails_helper"

RSpec.describe Search::WorkspaceIngestionService do
  it "indexes all supported sources, embeds chunks, and reports coverage" do
    user = User.create!(email: "ingest-service@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge ingest", slug: "knowledge-ingest")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    page = Page.create!(workspace: workspace, created_by: user, title: "Launch brief")
    Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: "Alex will circulate the launch checklist." } ] } ]
      }
    )

    database = Database.create!(workspace: workspace, name: "Tasks")
    row = DbRow.create!(workspace: workspace, database: database, title: "Prepare rollout", data_json: { notes: "Owner Sam" })

    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Launch review",
      description: "Errol to confirm approvals.",
      starts_at_utc: Time.zone.parse("2026-03-12 09:00:00"),
      ends_at_utc: Time.zone.parse("2026-03-12 10:00:00"),
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 15 ]
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Launch review recording",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      transcript_text: "[00:00] Errol: Alex will share the revised plan.",
      summary_markdown: "### Summary\n- Alex will share the revised plan."
    )
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "email-1",
      subject: "Launch email",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Alex emailed the revised launch plan."
    )

    allow(Openai::EmbeddingsClient).to receive(:embed_many_with_usage).and_return(
      {
        embeddings: Array.new(5) { [ 0.1, 0.2, 0.3 ] },
        usage: { prompt_tokens: 28, completion_tokens: 0, total_tokens: 28 }
      }
    )

    result = described_class.new(workspace: workspace, requested_by: user).call

    expect(result.source_count).to eq(5)
    expect(result.indexed_source_count).to eq(5)
    expect(result.coverage_percentage).to eq(100.0)
    expect(result.embedded_chunk_count).to be >= 5
    expect(result.missing_embedding_count).to eq(0)
    expect(SearchChunk.for_source(SearchChunk::SOURCE_MEETING_SESSION, session.id)).to exist
    expect(SearchChunk.for_source(SearchChunk::SOURCE_EPISTULARIUM_MESSAGE, message.id)).to exist
    expect(AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_SEMANTIC_BACKFILL)).to exist
  end
end
