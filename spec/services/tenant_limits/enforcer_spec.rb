require "rails_helper"

RSpec.describe TenantLimits::Enforcer do
  it "blocks AI use when the plan monthly cost cap has been reached" do
    user = User.create!(email: "limit-ai@example.com", password: "password123")
    workspace = Workspace.create!(name: "AI Cost Limit", slug: "ai-cost-limit")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(plan_key: WorkspaceSubscription::PLAN_STARTER)
    AiUsageLog.create!(
      workspace: workspace,
      user: user,
      operation: AiUsageLog::OP_ASSISTANT_QUERY,
      model: "gpt-test",
      prompt_tokens: 1,
      completion_tokens: 1,
      total_tokens: 2,
      estimated_cost_usd: 2.01
    )

    result = described_class.allowed?(workspace: workspace, feature: :ai)

    expect(result).not_to be_allowed
    expect(result.message).to include("cost allowance")
  end

  it "blocks incremental features when current usage is already at the limit" do
    owner = User.create!(email: "limit-members-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Member Limit", slug: "member-limit")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!(plan_key: WorkspaceSubscription::PLAN_STARTER, limits_json: { members: 1 })

    result = described_class.allowed?(workspace: workspace, feature: :members)

    expect(result).not_to be_allowed
    expect(result.message).to include("member limit")
  end
end
