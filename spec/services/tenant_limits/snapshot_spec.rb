require "rails_helper"

RSpec.describe TenantLimits::Snapshot do
  it "summarizes tenant usage against the active plan limits" do
    workspace = Workspace.create!(name: "Limit Snapshot", slug: "limit-snapshot")
    owner = User.create!(email: "limit-owner@example.com", password: "password123")
    member = User.create!(email: "limit-member@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    workspace.create_workspace_subscription!(plan_key: WorkspaceSubscription::PLAN_STARTER)
    AiUsageLog.create!(
      workspace: workspace,
      user: owner,
      operation: AiUsageLog::OP_ASSISTANT_QUERY,
      model: "gpt-test",
      prompt_tokens: 1,
      completion_tokens: 2,
      total_tokens: 3,
      estimated_cost_usd: 0.01
    )
    WorkspaceExport.create!(workspace: workspace, requested_by: owner)

    snapshot = described_class.new(workspace: workspace).call

    expect(snapshot[:plan_name]).to eq("Starter")
    expect(snapshot[:usage]).to include(
      members: 2,
      ai_requests_this_month: 1,
      exports_this_month: 1
    )
    expect(snapshot[:limits]).to include(
      members: 3,
      ai_requests_per_month: 1_000,
      exports_per_month: 100
    )
    expect(snapshot[:exceeded]).to include(
      members: false,
      ai_requests_per_month: false,
      exports_per_month: false
    )
  end
end
