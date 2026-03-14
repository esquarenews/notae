require "rails_helper"

RSpec.describe AgentActionEvent do
  it "chains event hashes so tampering invalidates the chain" do
    user = User.create!(email: "agent-action-event@example.com", password: "password123")
    workspace = Workspace.create!(name: "Agent Action Event", slug: "agent-action-event")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    agent_action = AgentAction.create!(
      workspace: workspace,
      user: user,
      title: "Review launch email",
      proposed_by: "manual",
      target_system: "gmail",
      draft_type: "email_draft",
      payload_json: { "to" => [ "team@example.com" ], "subject" => "Launch review" },
      approval_required: true,
      dry_run: true,
      status: AgentAction::STATUS_PENDING
    )

    first_event = described_class.record!(
      agent_action: agent_action,
      actor: user,
      event_type: "draft_created",
      details: { "title" => "Review launch email", "fields" => { "subject" => "Launch review" } }
    )
    second_event = described_class.record!(
      agent_action: agent_action,
      actor: user,
      event_type: "draft_updated",
      comment: "Adjusted the audience list",
      details: { "field" => "to" }
    )

    expect(first_event.sequence_number).to eq(1)
    expect(second_event.sequence_number).to eq(2)
    expect(second_event.previous_entry_hash).to eq(first_event.entry_hash)
    expect(first_event.hash_verification_succeeds?).to eq(true)
    expect(second_event.hash_verification_succeeds?).to eq(true)

    first_event.update_column(:comment, "tampered")

    expect(first_event.reload.hash_verification_succeeds?).to eq(false)
    expect(second_event.reload.hash_verification_succeeds?).to eq(false)
  end
end
