require "rails_helper"

RSpec.describe Search::QueueKnowledgeSuggestionRefreshJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before do
    clear_enqueued_jobs
  end

  it "queues daily and proactive generation for workspace members with API keys" do
    workspace = Workspace.create!(name: "Knowledge refresh", slug: "knowledge-refresh")
    melbourne_user = User.create!(
      email: "knowledge-refresh-melbourne@example.com",
      password: "password123",
      openai_api_key: "sk-test",
      time_zone: "Australia/Melbourne"
    )
    no_key_user = User.create!(
      email: "knowledge-refresh-no-key@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    Membership.create!(workspace: workspace, user: melbourne_user, role: :owner)
    Membership.create!(workspace: workspace, user: no_key_user, role: :member)

    allow(Search::PersistKnowledgeSuggestionService).to receive(:generation_context_available?).and_return(true)

    travel_to(Time.utc(2026, 3, 20, 23, 30, 0)) do
      described_class.perform_now(workspace.id)
    end

    expect(enqueued_jobs).to include(
      a_hash_including(
        job: Search::GenerateKnowledgeSuggestionJob,
        args: [ melbourne_user.id, workspace.id, KnowledgeSuggestion::KIND_DAILY_SUMMARY ]
      )
    )
    expect(enqueued_jobs).to include(
      a_hash_including(
        job: Search::GenerateKnowledgeSuggestionJob,
        args: [ melbourne_user.id, workspace.id, KnowledgeSuggestion::KIND_PROACTIVE ]
      )
    )
    expect(enqueued_jobs).not_to include(
      a_hash_including(
        job: Search::GenerateKnowledgeSuggestionJob,
        args: [ no_key_user.id, workspace.id, KnowledgeSuggestion::KIND_DAILY_SUMMARY ]
      )
    )
  end

  it "uses the user's local date when deciding whether today's daily brief already exists" do
    workspace = Workspace.create!(name: "Knowledge refresh existing", slug: "knowledge-refresh-existing")
    user = User.create!(
      email: "knowledge-refresh-existing@example.com",
      password: "password123",
      openai_api_key: "sk-test",
      time_zone: "Australia/Melbourne"
    )
    Membership.create!(workspace: workspace, user: user, role: :owner)
    KnowledgeSuggestion.create!(
      workspace: workspace,
      user: user,
      kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Daily workspace brief",
      summary: "Already generated for today. [1]",
      insights_json: [],
      task_suggestions_json: [],
      related_notes_json: [],
      sources_json: [],
      generated_for_date: Date.new(2026, 3, 21),
      generated_at: Time.utc(2026, 3, 20, 22, 45, 0)
    )

    allow(Search::PersistKnowledgeSuggestionService).to receive(:generation_context_available?).and_return(true)

    travel_to(Time.utc(2026, 3, 20, 20, 30, 0)) do
      described_class.perform_now(workspace.id)
    end

    expect(enqueued_jobs).to be_empty
  end
end
