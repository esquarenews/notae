require "rails_helper"

RSpec.describe AgentActions::PreviewBuilder do
  it "builds create previews for new drafts" do
    user = User.create!(email: "agent-preview-create@example.com", password: "password123")
    workspace = Workspace.create!(name: "Agent Preview Create", slug: "agent-preview-create")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: user,
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

    preview = described_class.new(agent_action).to_h

    expect(preview["mode"]).to eq("create")
    expect(preview["before"]).to be_nil
    expect(preview["changes"]).to include(
      a_hash_including("key" => "title", "after" => "Draft note"),
      a_hash_including("key" => "body", "after" => "Capture the rollout summary.")
    )
  end

  it "builds before and after previews once a draft is revised" do
    user = User.create!(email: "agent-preview-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Agent Preview Update", slug: "agent-preview-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: user,
      attributes: {
        title: "Draft issue comment",
        proposed_by: "manual",
        target_system: "github",
        draft_type: "github_comment_draft",
        payload_json: {
          "repository" => "org/repo",
          "target_reference" => "#42",
          "body" => "Initial comment."
        }
      }
    ).call

    AgentActions::UpdateService.new(
      agent_action: agent_action,
      actor: user,
      attributes: {
        title: "Draft issue comment v2",
        payload_json: {
          "repository" => "org/repo",
          "target_reference" => "#42",
          "body" => "Updated comment."
        }
      }
    ).call

    preview = described_class.new(agent_action.reload).to_h

    expect(preview["mode"]).to eq("update")
    expect(preview["before"]).to include(a_hash_including("key" => "body", "value" => "Initial comment."))
    expect(preview["changes"]).to include(
      a_hash_including("key" => "title", "before" => "Draft issue comment", "after" => "Draft issue comment v2"),
      a_hash_including("key" => "body", "before" => "Initial comment.", "after" => "Updated comment.")
    )
  end
end
