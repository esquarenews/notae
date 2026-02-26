require "rails_helper"

RSpec.describe Search::AiRateLimiter do
  around do |example|
    original_window = Rails.application.config.x.ai_search.rate_limit_window_seconds
    Rails.application.config.x.ai_search.rate_limit_window_seconds = 60
    Rails.cache.clear

    example.run
  ensure
    Rails.cache.clear
    Rails.application.config.x.ai_search.rate_limit_window_seconds = original_window
  end

  it "limits semantic search operations per user/workspace window" do
    user = User.create!(
      email: "ai-rate-user@example.com",
      password: "password123",
      ai_search_semantic_rate_limit_per_minute: 1
    )
    workspace = Workspace.create!(name: "AI Rate", slug: "ai-rate")

    first = described_class.allowed?(user: user, workspace: workspace, operation: "semantic_search")
    second = described_class.allowed?(user: user, workspace: workspace, operation: "semantic_search")

    expect(first).to eq(true)
    expect(second).to eq(false)
  end

  it "limits answer generation independently from semantic search" do
    user = User.create!(
      email: "ai-rate-answer@example.com",
      password: "password123",
      ai_search_semantic_rate_limit_per_minute: 1,
      ai_search_answer_rate_limit_per_minute: 1
    )
    workspace = Workspace.create!(name: "AI Rate Answer", slug: "ai-rate-answer")

    expect(described_class.allowed?(user: user, workspace: workspace, operation: "semantic_search")).to eq(true)
    expect(described_class.allowed?(user: user, workspace: workspace, operation: "answer_generation")).to eq(true)
    expect(described_class.allowed?(user: user, workspace: workspace, operation: "answer_generation")).to eq(false)
  end
end
