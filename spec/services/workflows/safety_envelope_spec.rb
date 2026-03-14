require "rails_helper"

RSpec.describe Workflows::SafetyEnvelope do
  after do
    AutomationControl.current.resume!
  end

  it "allows internal workflow launches when policy and kill switch permit them" do
    workspace = Workspace.create!(name: "Workflow Safety", slug: "workflow-safety")
    user = User.create!(email: "workflow-safety@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    decision = described_class.new(
      workspace: workspace,
      actor: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      confidence_score: 1.0
    ).evaluate

    expect(decision.allowed).to eq(true)
    expect(decision.allowed_actions).to include(WorkflowRun::KIND_CREATE_NOTA)
  end

  it "blocks workflows when the kill switch is active" do
    workspace = Workspace.create!(name: "Workflow Safety Kill", slug: "workflow-safety-kill")
    user = User.create!(email: "workflow-safety-kill@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    AutomationControl.current.pause!(reason: "Testing")

    decision = described_class.new(
      workspace: workspace,
      actor: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      confidence_score: 1.0
    ).evaluate

    expect(decision.allowed).to eq(false)
    expect(decision.reasons).to include("Automation kill switch is active")
  end
end
