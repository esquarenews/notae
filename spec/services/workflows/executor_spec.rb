require "rails_helper"

RSpec.describe Workflows::Executor do
  include ActiveJob::TestHelper

  after do
    clear_enqueued_jobs
    AutomationControl.current.resume!
  end

  it "creates internal nota pages successfully" do
    workspace = Workspace.create!(name: "Workflow Executor", slug: "workflow-executor")
    user = User.create!(email: "workflow-executor@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workflow_run = WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      status: WorkflowRun::STATUS_QUEUED,
      trigger_source: "manual",
      queued_at: Time.current,
      max_attempts: 1,
      confidence_score: 1.0,
      input_json: {
        "title" => "Automation note",
        "body" => "Created by the workflow executor."
      }
    )

    described_class.new(workflow_run: workflow_run).call

    workflow_run.reload
    expect(workflow_run.status).to eq(WorkflowRun::STATUS_SUCCEEDED)
    expect(workflow_run.result_json.fetch("target_type")).to eq("Page")
    expect(Page.find(workflow_run.result_json.fetch("target_id")).title).to eq("Automation note")
  end

  it "marks workflows as failed and notifies owners when execution cannot recover" do
    workspace = Workspace.create!(name: "Workflow Executor Failure", slug: "workflow-executor-failure")
    user = User.create!(email: "workflow-executor-failure@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workflow_run = WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: WorkflowRun::KIND_CREATE_TASK,
      status: WorkflowRun::STATUS_QUEUED,
      trigger_source: "manual",
      queued_at: Time.current,
      max_attempts: 1,
      confidence_score: 1.0,
      input_json: {
        "database_id" => SecureRandom.uuid,
        "title" => "Broken task"
      }
    )

    described_class.new(workflow_run: workflow_run).call

    workflow_run.reload
    expect(workflow_run.status).to eq(WorkflowRun::STATUS_FAILED)
    expect(workflow_run.error_message).to be_present
    notification = Notification.where(notification_type: Notification::TYPE_WORKFLOW_FAILED, notifiable: workflow_run).last
    expect(notification).to be_present
  end
end
