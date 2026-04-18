require "rails_helper"

RSpec.describe AgentActions::ReversalService do
  it "archives created pages when reversing approved nota drafts" do
    member = User.create!(email: "agent-reversal-member@example.com", password: "password123")
    owner = User.create!(email: "agent-reversal-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Agent Reversal", slug: "agent-reversal")
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft note",
        proposed_by: "manual",
        target_system: "notae",
        draft_type: "nota_draft",
        payload_json: {
          "title" => "Draft note",
          "body" => "Capture the rollout summary."
        }
      }
    ).call
    AgentActions::ApprovalService.new(agent_action: agent_action, actor: owner, comment: "Approved.").call
    created_page = Page.find(agent_action.reload.result_json.fetch("target_id"))

    described_class.new(agent_action: agent_action, actor: owner, comment: "Wrong place.").call

    expect(created_page.reload).to be_archived
    expect(agent_action.reload.reversed?).to eq(true)
    expect(agent_action.result_json.dig("reversal", "summary")).to eq("Archived the created Nota.")
  end
end
