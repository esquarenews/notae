require "rails_helper"

RSpec.describe AgentPolicy, type: :model do
  it "applies workspace defaults and exposes them via policy_snapshot" do
    workspace = Workspace.create!(name: "Agent Policy", slug: "agent-policy")

    policy = described_class.create!(workspace: workspace)

    expect(policy.allowed_target_systems).to eq(Search::AssistantQueryService::SUPPORTED_DRAFT_TARGETS)
    expect(policy.allowed_draft_types).to eq(AgentAction::DRAFT_TYPE_OPTIONS)
    expect(policy.allowed_lifecycle_operations).to eq(AgentActions::PolicyEngine::LIFECYCLE_OPTIONS)
    expect(policy.author_roles).to include("member", "admin", "owner", "automation_agent")
    expect(policy.approver_roles).to include("admin", "owner")
    expect(policy.policy_snapshot.fetch("approval_required")).to eq(true)
  end
end
