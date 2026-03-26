require "rails_helper"

RSpec.describe Search::PersistKnowledgeSuggestionService do
  include ActiveSupport::Testing::TimeHelpers

  it "keys daily summaries by the user's local date" do
    user = User.create!(
      email: "persist-knowledge@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Persist knowledge", slug: "persist-knowledge")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    service = described_class.new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY)

    travel_to Time.utc(2026, 3, 11, 20, 45, 0) do
      expect(service.send(:current_local_date)).to eq(Date.new(2026, 3, 12))
    end
  end

  it "does not create a proactive suggestion when nothing changed since the last report" do
    user = User.create!(
      email: "persist-knowledge-no-change@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne",
      openai_api_key: "sk-test"
    )
    workspace = Workspace.create!(name: "Persist knowledge no change", slug: "persist-knowledge-no-change")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Stable brief")
    chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "No new updates are present.",
      token_count: 5,
      content_hash: "persist-no-change-1",
      source_content_hash: "persist-no-change-source-1",
      source_uri: "/w/#{workspace.slug}/pages/#{page.id}",
      source_title: page.title,
      metadata_json: {}
    )
    chunk.update_columns(updated_at: 3.hours.ago)

    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "No new updates are present. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      metadata_json: {
        "context_snapshot" => [
          {
            "source_type" => SearchChunk::SOURCE_PAGE,
            "source_id" => page.id,
            "source_title" => page.title,
            "source_content_hash" => "persist-no-change-source-1",
            "updated_at" => 3.hours.ago.iso8601
          }
        ]
      },
      generated_for_date: Date.current,
      generated_at: 2.hours.ago
    )

    expect(Openai::ResponsesClient).not_to receive(:generate_text_with_usage)

    result = described_class.new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE).call

    expect(result).to be_nil
    expect(KnowledgeSuggestion.for_user(user).for_workspace(workspace).proactive).to be_empty
  end

  it "stores proactive reports as delta updates against the latest report" do
    user = User.create!(
      email: "persist-knowledge-delta@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne",
      openai_api_key: "sk-test"
    )
    workspace = Workspace.create!(name: "Persist knowledge delta", slug: "persist-knowledge-delta")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    old_page = Page.create!(workspace: workspace, created_by: user, title: "Earlier brief")
    new_page = Page.create!(workspace: workspace, created_by: user, title: "Fresh brief")

    old_chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: old_page.id,
      page: old_page,
      chunk_index: 0,
      text: "Earlier brief already discussed.",
      token_count: 4,
      content_hash: "persist-delta-old-1",
      source_content_hash: "persist-delta-source-old-1",
      source_uri: "/w/#{workspace.slug}/pages/#{old_page.id}",
      source_title: old_page.title,
      metadata_json: {}
    )
    new_chunk = SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: new_page.id,
      page: new_page,
      chunk_index: 0,
      text: "Fresh brief says Errol will confirm the rollout timing.",
      token_count: 9,
      content_hash: "persist-delta-new-1",
      source_content_hash: "persist-delta-source-new-1",
      source_uri: "/w/#{workspace.slug}/pages/#{new_page.id}",
      source_title: new_page.title,
      metadata_json: { "entities" => { "names" => [ "Errol" ] } }
    )
    old_chunk.update_columns(updated_at: 3.hours.ago)
    new_chunk.update_columns(updated_at: 20.minutes.ago)

    previous = KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "Earlier brief already discussed. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      metadata_json: {
        "context_snapshot" => [
          {
            "source_type" => SearchChunk::SOURCE_PAGE,
            "source_id" => old_page.id,
            "source_title" => old_page.title,
            "source_content_hash" => "persist-delta-source-old-1",
            "updated_at" => 3.hours.ago.iso8601
          }
        ]
      },
      generated_for_date: Date.current,
      generated_at: 2.hours.ago
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: {
          summary: "Rollout timing now needs Errol's confirmation. [1]",
          insights: [ "Errol is named in the fresh brief. [1]" ],
          task_suggestions: [
            {
              title: "Confirm rollout timing",
              owner: "Errol",
              rationale: "The fresh brief says Errol will confirm timing. [1]",
              citation_indices: [ 1 ]
            }
          ],
          related_notes: []
        }.to_json,
        usage: { prompt_tokens: 22, completion_tokens: 18, total_tokens: 40 }
      }
    )

    suggestion = described_class.new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE).call

    expect(suggestion).to be_present
    expect(suggestion.kind).to eq(KnowledgeSuggestion::KIND_PROACTIVE)
    expect(suggestion.title).to eq("Confirm rollout timing")
    expect(suggestion.metadata_json["report_mode"]).to eq(Search::KnowledgeSuggestionService::MODE_DELTA)
    expect(suggestion.metadata_json["baseline_generated_at"]).to eq(previous.generated_at.iso8601)
    expect(suggestion.metadata_json.fetch("context_snapshot").first.fetch("source_title")).to eq("Fresh brief")
    expect(suggestion.sources_json.first.fetch("title")).to eq("Fresh brief")
    notification = Notification.where(
      recipient: user,
      workspace: workspace,
      notifiable: suggestion,
      notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY
    ).last
    expect(notification).to be_present
    expect(notification.metadata).to include("kind" => KnowledgeSuggestion::KIND_PROACTIVE, "title" => "Confirm rollout timing")
  end
end
