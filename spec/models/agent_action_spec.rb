require "rails_helper"

RSpec.describe AgentAction, type: :model do
  it "validates supported target systems and required email payload fields" do
    workspace = Workspace.create!(name: "Agent Action Model", slug: "agent-action-model")
    user = User.create!(email: "agent-action-model@example.com", password: "password123")

    agent_action = described_class.new(
      workspace: workspace,
      user: user,
      title: "Broken task draft",
      proposed_by: "manual",
      target_system: "gmail",
      draft_type: "task_ticket",
      status: described_class::STATUS_PENDING,
      approval_required: true,
      dry_run: true,
      payload_json: {
        "project" => "",
        "title" => "",
        "body" => ""
      }
    )

    expect(agent_action).not_to be_valid
    expect(agent_action.errors[:target_system]).to include("is not supported for task ticket")
    expect(agent_action.errors[:payload_json]).to include("must include a destination project or queue")
    expect(agent_action.errors[:payload_json]).to include("must include a ticket title")
    expect(agent_action.errors[:payload_json]).to include("must include ticket details")
  end

  it "keeps changes-requested drafts editable" do
    workspace = Workspace.create!(name: "Agent Action Editable", slug: "agent-action-editable")
    user = User.create!(email: "agent-action-editable@example.com", password: "password123")

    agent_action = described_class.new(
      workspace: workspace,
      user: user,
      title: "Calendar hold",
      proposed_by: "manual",
      target_system: "calendar",
      draft_type: "calendar_hold",
      status: described_class::STATUS_CHANGES_REQUESTED,
      approval_required: true,
      dry_run: true,
      payload_json: {
        "title" => "Project review",
        "starts_at" => "2026-03-20T09:00",
        "ends_at" => "2026-03-20T09:30"
      }
    )

    expect(agent_action).to be_valid
    expect(agent_action).to be_editable
  end
end
