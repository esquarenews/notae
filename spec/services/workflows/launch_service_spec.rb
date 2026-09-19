require "rails_helper"

RSpec.describe Workflows::LaunchService do
  include ActiveJob::TestHelper

  after do
    clear_enqueued_jobs
    AutomationControl.current.resume!
  end

  it "executes inline without queueing an execution job" do
    workspace, user = create_workspace_and_owner("inline")

    workflow_run = described_class.new(
      workspace: workspace,
      actor: user,
      workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
      input: { title: "Inline nota", body: "# Finished inline" },
      trigger_source: "ai_assistant",
      confidence_score: 1.0,
      execution_mode: "inline"
    ).call

    expect(workflow_run).to be_succeeded
    expect(Page.find(workflow_run.result_json.fetch("target_id")).title).to eq("Inline nota")
    expect(enqueued_jobs.map { |job| job.fetch(:job) }).not_to include(Workflows::ExecuteRunJob)
  end

  it "queues execution asynchronously by default" do
    workspace, user = create_workspace_and_owner("async")

    expect do
      workflow_run = described_class.new(
        workspace: workspace,
        actor: user,
        workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
        input: { title: "Queued nota", body: "Queued body" }
      ).call
      expect(workflow_run).to be_queued
    end.to have_enqueued_job(Workflows::ExecuteRunJob)
  end

  it "rejects unsupported execution modes before creating a run" do
    workspace, user = create_workspace_and_owner("invalid-mode")
    original_count = WorkflowRun.count

    expect do
      described_class.new(
        workspace: workspace,
        actor: user,
        workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
        input: { title: "Never", body: "Never" },
        execution_mode: "immediate"
      ).call
    end.to raise_error(described_class::Error, "Unsupported workflow execution mode")
    expect(WorkflowRun.count).to eq(original_count)
  end

  it "rejects locked database targets before queueing a task" do
    workspace, user = create_workspace_and_owner("locked-target")
    database = workspace.databases.create!(name: "Locked", created_by: user, locked: true)
    original_count = WorkflowRun.count

    expect do
      described_class.new(
        workspace: workspace,
        actor: user,
        workflow_kind: WorkflowRun::KIND_CREATE_TASK,
        input: { database_id: database.id, title: "Blocked" }
      ).call
    end.to raise_error(described_class::Error, /Grid is locked/)
    expect(WorkflowRun.count).to eq(original_count)
  end

  it "rejects provider calendars whose connection is disabled" do
    workspace, user = create_workspace_and_owner("disabled-provider")
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Disabled provider",
      access_token: "token",
      enabled: false
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Disabled primary",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )

    expect do
      described_class.new(
        workspace: workspace,
        actor: user,
        workflow_kind: WorkflowRun::KIND_CREATE_CALENDAR_EVENT,
        input: {
          kalendarium_calendar_id: calendar.id,
          title: "Must not sync",
          starts_at: "2026-07-20 09:00 UTC",
          ends_at: "2026-07-20 10:00 UTC"
        }
      ).call
    end.to raise_error(described_class::Error, /writable calendar/)
  end

  def create_workspace_and_owner(suffix)
    workspace = Workspace.create!(name: "Launch #{suffix.titleize}", slug: "launch-#{suffix}")
    user = User.create!(email: "launch-#{suffix}@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    [ workspace, user ]
  end
end
