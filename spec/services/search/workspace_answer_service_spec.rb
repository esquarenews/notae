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

    allow(Openai::ResponsesClient).to receive(:generate_text).and_return("Launch starts this week [1]. Owners are listed in milestones [2].")

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
  end
end
