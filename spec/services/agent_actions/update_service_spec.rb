require "rails_helper"

RSpec.describe AgentActions::UpdateService do
  it "resubmits drafts after requested changes and notifies approvers" do
    workspace = Workspace.create!(name: "Update Service", slug: "update-service")
    author = User.create!(email: "update-service-author@example.com", password: "password123")
    approver = User.create!(email: "update-service-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft issue handoff",
        proposed_by: "manual",
        target_system: "github",
        draft_type: "github_comment_draft",
        payload_json: {
          "repository" => "org/repo",
          "target_reference" => "#42",
          "body" => "Initial draft."
        }
      }
    ).call

    AgentActions::RequestChangesService.new(
      agent_action: agent_action,
      actor: approver,
      comment: "Please mention rollout timing."
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: author,
      attributes: {
        title: "Draft issue handoff v2",
        payload_json: {
          "repository" => "org/repo",
          "target_reference" => "#42",
          "body" => "Updated draft with rollout timing."
        }
      },
      comment: "Added the rollout timing detail."
    ).call

    agent_action.reload

    expect(agent_action.status).to eq(AgentAction::STATUS_PENDING)
    expect(agent_action.title).to eq("Draft issue handoff v2")
    expect(agent_action.review_history.pluck(:event_type)).to include("draft_updated", "resubmitted")
    notification = Notification.where(recipient: approver, notifiable: agent_action, notification_type: Notification::TYPE_AGENT_ACTION_RESUBMITTED).last
    expect(notification).to be_present
  end
end
