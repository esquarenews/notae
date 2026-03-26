require "rails_helper"

RSpec.describe Search::AiUsageLogger do
  it "persists token usage with an estimated cost" do
    user = User.create!(email: "ai-usage-user@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Usage", slug: "ai-usage")

    described_class.log!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_SEARCH_ANSWER,
      model: "gpt-4o-mini",
      usage: { prompt_tokens: 2000, completion_tokens: 1000, total_tokens: 3000 },
      metadata: { source: "spec" }
    )

    usage = AiUsageLog.find_by!(user: user, workspace: workspace, operation: AiUsageLog::OP_SEARCH_ANSWER)
    expect(usage.total_tokens).to eq(3000)
    expect(usage.estimated_cost_usd.to_f).to be > 0
    expect(usage.metadata).to include("source" => "spec")
  end

  it "persists zero-token outcome rows for analytics-only events" do
    user = User.create!(email: "ai-usage-outcome@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Usage Outcome", slug: "ai-usage-outcome")

    described_class.log_outcome!(
      user: user,
      workspace: workspace,
      operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS,
      model: "gpt-4.1-mini",
      metadata: { reason: "no_context" }
    )

    usage = AiUsageLog.find_by!(user: user, workspace: workspace, operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS)
    expect(usage.total_tokens).to eq(0)
    expect(usage.estimated_cost_usd.to_f).to eq(0.0)
    expect(usage.metadata).to include("reason" => "no_context")
  end
end
