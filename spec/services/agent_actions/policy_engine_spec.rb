require "rails_helper"

RSpec.describe AgentActions::PolicyEngine do
  it "allows members to draft supported actions and requires approval" do
    workspace = Workspace.create!(name: "Policy Engine", slug: "policy-engine")
    member = User.create!(email: "policy-engine-member@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: member, role: :member)

    decision = described_class.new(
      workspace: workspace,
      actor: member,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate

    expect(decision.allowed).to eq(true)
    expect(decision.role).to eq("member")
    expect(decision.approval_required).to eq(true)
    expect(decision.dry_run_only).to eq(true)
    expect(decision.reasons).to eq([])
  end

  it "allows workspace admins to approve drafts" do
    workspace = Workspace.create!(name: "Policy Engine Admin", slug: "policy-engine-admin")
    owner = User.create!(email: "policy-engine-owner@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "github",
      draft_type: "github_comment_draft",
      lifecycle_operation: described_class::LIFECYCLE_APPROVE
    ).evaluate

    expect(decision.allowed).to eq(true)
    expect(decision.role).to eq("owner")
  end

  it "rejects approval by non-admin members" do
    workspace = Workspace.create!(name: "Policy Engine Reject", slug: "policy-engine-reject")
    member = User.create!(email: "policy-engine-reject@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: member, role: :member)

    decision = described_class.new(
      workspace: workspace,
      actor: member,
      target_system: "github",
      draft_type: "github_comment_draft",
      lifecycle_operation: described_class::LIFECYCLE_APPROVE
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.reasons).to include("Your role cannot perform this action under workspace policy")
  end

  it "keeps auditors read-only" do
    workspace = Workspace.create!(name: "Policy Engine Auditor", slug: "policy-engine-auditor")
    auditor = User.create!(email: "policy-engine-auditor@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: auditor, role: :auditor)

    decision = described_class.new(
      workspace: workspace,
      actor: auditor,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.role).to eq("auditor")
    expect(decision.reasons).to include("Auditors are read-only")
  end

  it "lets automation agent memberships create drafts but not approve them" do
    workspace = Workspace.create!(name: "Policy Engine Automation Agent", slug: "policy-engine-automation-agent")
    automation_agent = User.create!(email: "policy-engine-automation-agent@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: automation_agent, role: :automation_agent)

    draft_decision = described_class.new(
      workspace: workspace,
      actor: automation_agent,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate
    approve_decision = described_class.new(
      workspace: workspace,
      actor: automation_agent,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_APPROVE
    ).evaluate

    expect(draft_decision.allowed).to eq(true)
    expect(draft_decision.role).to eq("automation_agent")
    expect(approve_decision.allowed).to eq(false)
    expect(approve_decision.reasons).to include("Your role cannot perform this action under workspace policy")
  end

  it "rejects unsupported system and draft combinations" do
    workspace = Workspace.create!(name: "Policy Engine Unsupported", slug: "policy-engine-unsupported")
    owner = User.create!(email: "policy-engine-unsupported@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "gmail",
      draft_type: "task_ticket",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.reasons).to include("Adapter does not support this draft type")
  end

  it "rejects guests from drafting external actions" do
    workspace = Workspace.create!(name: "Policy Engine Guest", slug: "policy-engine-guest")
    guest = User.create!(email: "policy-engine-guest@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: guest, role: :guest)

    decision = described_class.new(
      workspace: workspace,
      actor: guest,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.reasons).to include("Guests cannot manage external action drafts")
  end

  it "enforces persisted workspace policy overrides" do
    workspace = Workspace.create!(name: "Policy Engine Overrides", slug: "policy-engine-overrides")
    owner = User.create!(email: "policy-engine-overrides@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    AgentPolicy.create!(
      workspace: workspace,
      allowed_target_systems_json: [ "gmail" ],
      allowed_draft_types_json: [ "email_draft" ],
      allowed_lifecycle_operations_json: [ described_class::LIFECYCLE_DRAFT ],
      author_roles_json: [ "owner" ],
      approver_roles_json: [ "owner" ],
      approval_required: true,
      dry_run_required: true,
      max_estimated_cost_usd: 0.25
    )

    decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "github",
      draft_type: "github_comment_draft",
      lifecycle_operation: described_class::LIFECYCLE_APPROVE,
      estimated_cost_usd: 0.5
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.policy_id).to be_present
    expect(decision.reasons).to include("Target system is blocked by workspace policy")
    expect(decision.reasons).to include("Draft type is blocked by workspace policy")
    expect(decision.reasons).to include("Lifecycle operation is blocked by workspace policy")
    expect(decision.reasons).to include("Estimated cost exceeds workspace policy")
  end

  it "can require approval for specific draft types even when global approval is off" do
    workspace = Workspace.create!(name: "Policy Engine Draft Approval", slug: "policy-engine-draft-approval")
    owner = User.create!(email: "policy-engine-draft-approval@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    AgentPolicy.create!(
      workspace: workspace,
      approval_required: false,
      dry_run_required: true,
      approval_required_draft_types_json: [ "calendar_hold" ]
    )

    email_decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "gmail",
      draft_type: "email_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate
    calendar_decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "calendar",
      draft_type: "calendar_hold",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT
    ).evaluate

    expect(email_decision.approval_required).to eq(false)
    expect(calendar_decision.approval_required).to eq(true)
  end

  it "forces approval for agent-authored internal drafts in shared workspaces" do
    workspace = Workspace.create!(name: "Policy Engine Shared Internal", slug: "policy-engine-shared-internal")
    owner = User.create!(email: "policy-engine-shared-internal-owner@example.com", password: "password123")
    collaborator = User.create!(email: "policy-engine-shared-internal-collab@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: collaborator, role: :member)
    AgentPolicy.create!(
      workspace: workspace,
      approval_required: false,
      dry_run_required: false
    )

    decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "notae",
      draft_type: "nota_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT,
      proposed_by: "api"
    ).evaluate

    expect(decision.allowed).to eq(true)
    expect(decision.approval_required).to eq(true)
    expect(decision.safety_overrides).to include(described_class::SHARED_WORKSPACE_APPROVAL_OVERRIDE)
    expect(decision.policy_snapshot.fetch("effective_approval_required")).to eq(true)
  end

  it "preserves workspace approval settings for manual drafts in shared workspaces" do
    workspace = Workspace.create!(name: "Policy Engine Shared Manual", slug: "policy-engine-shared-manual")
    owner = User.create!(email: "policy-engine-shared-manual-owner@example.com", password: "password123")
    collaborator = User.create!(email: "policy-engine-shared-manual-collab@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: collaborator, role: :member)
    AgentPolicy.create!(
      workspace: workspace,
      approval_required: false,
      dry_run_required: false
    )

    decision = described_class.new(
      workspace: workspace,
      actor: owner,
      target_system: "notae",
      draft_type: "nota_draft",
      lifecycle_operation: described_class::LIFECYCLE_DRAFT,
      proposed_by: "manual"
    ).evaluate

    expect(decision.allowed).to eq(true)
    expect(decision.approval_required).to eq(false)
    expect(decision.safety_overrides).to eq([])
    expect(decision.policy_snapshot.fetch("effective_approval_required")).to eq(false)
  end
end
