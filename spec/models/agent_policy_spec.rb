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
    expect(policy.allowed_internal_actions).to include("update_nota", "create_database")
    expect(policy.policy_snapshot.fetch("approval_required")).to eq(true)
    expect(policy.policy_snapshot.fetch("approval_required_draft_types")).to eq([])
  end

  it "preserves explicitly restricted internal action policies" do
    legacy_workspace = Workspace.create!(name: "Legacy Agent Policy", slug: "legacy-agent-policy")
    restricted_workspace = Workspace.create!(name: "Restricted Agent Policy", slug: "restricted-agent-policy")
    legacy_policy = described_class.create!(
      workspace: legacy_workspace,
      allowed_internal_actions_json: %w[create_nota create_task create_calendar_event]
    )
    restricted_policy = described_class.create!(
      workspace: restricted_workspace,
      allowed_internal_actions_json: %w[create_nota create_task]
    )

    expect(legacy_policy.allowed_internal_actions).to eq(%w[create_nota create_task create_calendar_event])
    expect(restricted_policy.allowed_internal_actions).to eq(%w[create_nota create_task])
  end
end
