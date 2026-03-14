require "rails_helper"

RSpec.describe "Workflow runs", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    clear_enqueued_jobs
    perform_enqueued_jobs { example.run }
  ensure
    clear_enqueued_jobs
    AutomationControl.current.resume!
  end

  it "queues and executes an internal nota workflow" do
    workspace = Workspace.create!(name: "Workflow Requests", slug: "workflow-requests")
    user = User.create!(email: "workflow-requests@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    expect {
      post workflow_runs_path(workspace_slug: workspace.slug), params: {
        workflow_run: {
          workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
          confidence_score: "1.0",
          title: "Workflow generated nota",
          body: "This note came from the workflow engine."
        }
      }
    }.to change(WorkflowRun, :count).by(1).and change(Page, :count).by(1)

    workflow_run = WorkflowRun.order(:created_at).last
    expect(response).to redirect_to(workflow_run_path(workspace_slug: workspace.slug, id: workflow_run.id))
    expect(workflow_run.reload.status).to eq(WorkflowRun::STATUS_SUCCEEDED)

    get workflow_runs_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Workflow Runs")
    expect(response.body).to include("Run history")
  end

  it "blocks workflow launches while the kill switch is active" do
    workspace = Workspace.create!(name: "Workflow Requests Kill", slug: "workflow-requests-kill")
    user = User.create!(email: "workflow-requests-kill@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    AutomationControl.current.pause!(reason: "Maintenance")
    sign_in user

    post workflow_runs_path(workspace_slug: workspace.slug), params: {
      workflow_run: {
        workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
        confidence_score: "1.0",
        title: "Blocked",
        body: "Should not run."
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Automation kill switch is active")
  end
end
