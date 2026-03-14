require "rails_helper"

RSpec.describe AgentActions::RequestChangesService do
  it "moves drafts into changes-requested state and notifies the author" do
    workspace = Workspace.create!(name: "Request Changes Service", slug: "request-changes-service")
    author = User.create!(email: "request-changes-author@example.com", password: "password123")
    approver = User.create!(email: "request-changes-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft follow-up email",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [],
          "subject" => "Follow up",
          "body" => "Please review the notes."
        }
      }
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: approver,
      comment: "Add the customer timeline before approval."
    ).call

    agent_action.reload

    expect(agent_action.status).to eq(AgentAction::STATUS_CHANGES_REQUESTED)
    expect(agent_action.review_history.find_by!(event_type: "changes_requested").comment).to eq("Add the customer timeline before approval.")
    notification = Notification.where(recipient: author, notifiable: agent_action).order(:created_at).last
    expect(notification.notification_type).to eq(Notification::TYPE_AGENT_ACTION_CHANGES_REQUESTED)
    expect(notification.metadata["comment"]).to eq("Add the customer timeline before approval.")
  end
end
