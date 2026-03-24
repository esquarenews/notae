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

  it "builds delta suggestions only from changed context since the last report" do
    user = User.create!(email: "knowledge-delta@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge delta", slug: "knowledge-delta")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    old_page = Page.create!(workspace: workspace, created_by: user, title: "Old brief")
    new_page = Page.create!(workspace: workspace, created_by: user, title: "New brief")

    old_chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: old_page.id,
      page: old_page,
      chunk_index: 0,
      text: "Old context that was already reported.",
      token_count: 6,
      content_hash: "chunk-old-1",
      source_content_hash: "source-old-1",
      source_uri: "/w/#{workspace.slug}/pages/#{old_page.id}",
      source_title: old_page.title,
      metadata_json: { "entities" => { "names" => [ "Alex" ] } }
    )
    new_chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: new_page.id,
      page: new_page,
      chunk_index: 0,
      text: "Fresh update says Sam will close the launch blockers.",
      token_count: 9,
      content_hash: "chunk-new-1",
      source_content_hash: "source-new-1",
      source_uri: "/w/#{workspace.slug}/pages/#{new_page.id}",
      source_title: new_page.title,
      metadata_json: { "entities" => { "names" => [ "Sam" ] } }
    )
    old_chunk.update_columns(updated_at: 3.hours.ago)
    new_chunk.update_columns(updated_at: 30.minutes.ago)

    previous_report = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "Old brief already covered. [1]",
      insights_json: [ "Alex owned the previous handoff. [1]" ],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      metadata_json: {
        "context_snapshot" => [
          {
            "source_type" => SearchChunk::SOURCE_PAGE,
            "source_id" => old_page.id,
            "source_title" => old_page.title,
            "source_content_hash" => "source-old-1",
            "updated_at" => 3.hours.ago.iso8601
          }
        ]
      },
      generated_for_date: Date.current,
      generated_at: 2.hours.ago
    )

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:prompt]).to include("new or materially changed")
      expect(args[:prompt]).to include("Previous report")
      expect(args[:prompt]).to include("New brief")
      {
        text: {
          summary: "Sam has a new blocker-closing task. [1]",
          insights: [ "Sam is now the named owner of the update. [1]" ],
          task_suggestions: [
            {
              title: "Confirm blocker closure",
              owner: "Sam",
              rationale: "The new brief says Sam will close the blockers. [1]",
              citation_indices: [ 1 ]
            }
          ],
          related_notes: []
        }.to_json,
        usage: { prompt_tokens: 30, completion_tokens: 16, total_tokens: 46 }
      }
    end

    response = described_class.new(
      user: user,
      workspace: workspace,
      mode: described_class::MODE_DELTA,
      since: 2.hours.ago,
      previous_report: previous_report
    ).call

    expect(response).to be_present
    expect(response.report_mode).to eq(described_class::MODE_DELTA)
    expect(response.sources.length).to eq(1)
    expect(response.sources.first[:title]).to eq("New brief")
    expect(response.context_snapshot.first.fetch("source_title")).to eq("New brief")
  end

  it "filters stale emails and rewrites the current user to second person" do
    user = User.create!(email: "errol.schmidt@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Knowledge freshness", slug: "knowledge-freshness")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "errol.schmidt@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    stale_message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "old-msg-1",
      subject: "Ancient follow-up",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Please send the invoice.",
      received_at: 1.year.ago
    )
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_EPISTULARIUM_MESSAGE,
      source_id: stale_message.id,
      epistularium_message: stale_message,
      chunk_index: 0,
      text: stale_message.search_source_text,
      token_count: 12,
      content_hash: "email-old-1",
      source_content_hash: "email-old-source-1",
      source_uri: "/w/#{workspace.slug}/epistularium/messages/#{stale_message.id}",
      source_title: stale_message.display_subject,
      metadata_json: {
        "received_at" => stale_message.received_at.iso8601
      }
    )

    page = Page.create!(workspace: workspace, created_by: user, title: "Launch blockers")
    fresh_chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Errol Schmidt needs to confirm the blocker timing today.",
      token_count: 9,
      content_hash: "fresh-page-1",
      source_content_hash: "fresh-page-source-1",
      source_uri: "/w/#{workspace.slug}/pages/#{page.id}",
      source_title: page.title,
      metadata_json: { "entities" => { "names" => [ "Errol Schmidt" ] } }
    )
    fresh_chunk.update_columns(updated_at: 10.minutes.ago)

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:prompt]).to include("Current user email: errol.schmidt@example.com")
      expect(args[:prompt]).to include("refer to them as \"you\"")
      expect(args[:prompt]).not_to include("Ancient follow-up")
      {
        text: {
          summary: "Errol Schmidt should confirm the blocker timing today. [1]",
          insights: [ "Errol Schmidt is the named owner of the current follow-up. [1]" ],
          task_suggestions: [
            {
              title: "Confirm blocker timing",
              owner: "Errol Schmidt",
              rationale: "Errol Schmidt should confirm the blocker timing today. [1]",
              citation_indices: [ 1 ]
            }
          ],
          related_notes: []
        }.to_json,
        usage: { prompt_tokens: 40, completion_tokens: 20, total_tokens: 60 }
      }
    end

    response = described_class.new(user: user, workspace: workspace).call

    expect(response.summary).to include("You should confirm")
    expect(response.insights.first).to include("You")
    expect(response.task_suggestions.first.fetch("owner")).to eq("You")
    expect(response.task_suggestions.first.fetch("rationale")).to include("You should confirm")
    expect(response.sources.first[:title]).to eq(page.title)
  end
end
