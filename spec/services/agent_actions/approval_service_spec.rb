require "rails_helper"

RSpec.describe AgentActions::ApprovalService do
  it "approves drafts in dry-run mode and logs the decision trail" do
    workspace = Workspace.create!(name: "Approval Service", slug: "approval-service")
    author = User.create!(email: "approval-service-author@example.com", password: "password123")
    approver = User.create!(email: "approval-service-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft rollout note",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [ "approvals@example.com" ],
          "subject" => "Rollout note",
          "body" => "Please review the rollout."
        }
      }
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: approver,
      comment: "Looks safe to send once live adapters exist."
    ).call

    agent_action.reload

    expect(agent_action.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.approved_by).to eq(approver)
    expect(agent_action.approved_at).to be_present
    expect(agent_action.executed_at).to be_present
    expect(agent_action.result_json.fetch("dry_run")).to eq(true)
    expect(agent_action.result_json.fetch("target_system")).to eq("gmail")
    expect(agent_action.result_json.fetch("summary")).to include("No message was sent")

    expect(agent_action.review_history.pluck(:event_type)).to eq(
      %w[policy_evaluated draft_created policy_evaluated approved tool_used]
    )
    expect(agent_action.review_history.find_by!(event_type: "approved").comment).to eq("Looks safe to send once live adapters exist.")
    approval_notification = Notification.where(recipient: author, notifiable: agent_action).order(:created_at).last
    expect(approval_notification.notification_type).to eq(Notification::TYPE_AGENT_ACTION_APPROVED)

    audit_actions = AuditEvent.where(auditable: agent_action).order(:created_at).pluck(:action)
    expect(audit_actions).to include(
      "agent_action_policy_evaluated",
      "agent_action_draft_created",
      "agent_action_approved",
      "agent_action_tool_used"
    )
  end
end
