require "rails_helper"

RSpec.describe Search::WorkspaceAnswerService do
  it "returns nil when OpenAI key is not configured" do
    user = User.create!(email: "answer-no-key@example.com", password: "password123")
    workspace = Workspace.create!(name: "Answer No Key", slug: "answer-no-key")

    result = described_class.new(
      user: user,
      workspace: workspace,
      query: "What is the launch plan?",
      results: []
    ).call

    expect(result).to be_nil
  end

  it "returns AI summary and source citations for top results" do
    user = User.create!(email: "answer-key@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Answer Key", slug: "answer-key")
    results = [
      Search::WorkspaceSearchService::Result.new(
        kind: "Page",
        title: "Launch Plan",
        excerpt: "<mark>launch</mark> timeline and scope",
        url: "/w/answer-key/pages/page-1",
        score: 42
      ),
      Search::WorkspaceSearchService::Result.new(
        kind: "Row",
        title: "Milestone Row",
        excerpt: "Owners and dates",
        url: "/w/answer-key/databases/db-1#row_1",
        score: 30
      )
    ]

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Launch starts this week [1]. Owners are listed in milestones [2].",
        usage: { prompt_tokens: 120, completion_tokens: 34, total_tokens: 154 }
      }
    )

    answer = described_class.new(
      user: user,
      workspace: workspace,
      query: "When does launch start?",
      results: results
    ).call

    expect(answer).to be_present
    expect(answer.summary).to include("Launch starts this week")
    expect(answer.sources.length).to eq(2)
    expect(answer.sources.first).to include(index: 1, title: "Launch Plan", kind: "Page")
    expect(answer.sources.second).to include(index: 2, title: "Milestone Row", kind: "Row")
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_SEARCH_ANSWER)
    expect(usage).to exist
  end

  it "returns nil when answer rate limiting blocks the operation" do
    user = User.create!(email: "answer-rate-limit@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Answer Guardrail", slug: "answer-guardrail")
    results = [
      Search::WorkspaceSearchService::Result.new(kind: "Page", title: "Roadmap", excerpt: "scope", url: "/roadmap", score: 20)
    ]

    expect(Search::AiRateLimiter).to receive(:allowed?)
      .with(user: user, workspace: workspace, operation: "answer_generation")
      .and_return(false)
    expect(Openai::ResponsesClient).not_to receive(:generate_text_with_usage)

    answer = described_class.new(
      user: user,
      workspace: workspace,
      query: "What changed?",
      results: results
    ).call

    expect(answer).to be_nil
  end
end
