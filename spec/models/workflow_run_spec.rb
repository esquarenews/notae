require "rails_helper"

RSpec.describe WorkflowRun, type: :model do
  it "tracks queued and finished workflow states" do
    workspace = Workspace.create!(name: "Workflow Run", slug: "workflow-run")
    user = User.create!(email: "workflow-run@example.com", password: "password123")

    run = described_class.create!(
      workspace: workspace,
      user: user,
      workflow_kind: described_class::KIND_CREATE_NOTA,
      status: described_class::STATUS_QUEUED,
      trigger_source: "manual",
      queued_at: Time.current,
      confidence_score: 1.0
    )

    expect(run).to be_queued
    expect(run).not_to be_finished

    run.update!(status: described_class::STATUS_SUCCEEDED, finished_at: Time.current)
    expect(run).to be_succeeded
    expect(run).to be_finished
  end
end
