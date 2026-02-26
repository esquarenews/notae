require "rails_helper"

RSpec.describe Search::AiBudgetGuard do
  it "allows operations when spend is below budget" do
    user = User.create!(
      email: "ai-budget-ok@example.com",
      password: "password123",
      ai_search_daily_budget_usd: 0.05
    )
    workspace = Workspace.create!(name: "AI Budget Ok", slug: "ai-budget-ok")

    expect(described_class.within_daily_budget?(user: user, workspace: workspace)).to eq(true)
  end

  it "blocks operations when spend reaches budget" do
    user = User.create!(
      email: "ai-budget-block@example.com",
      password: "password123",
      ai_search_daily_budget_usd: 0.01
    )
    workspace = Workspace.create!(name: "AI Budget Block", slug: "ai-budget-block")
    AiUsageLog.create!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_SEARCH_ANSWER,
      model: "gpt-4o-mini",
      prompt_tokens: 100,
      completion_tokens: 50,
      total_tokens: 150,
      estimated_cost_usd: 0.02
    )

    expect(described_class.within_daily_budget?(user: user, workspace: workspace)).to eq(false)
  end
end
