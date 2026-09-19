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
    page = Page.find(workflow_run.result_json.fetch("target_id"))
    expect(page.title).to eq("Automation note")
    expect(page.blocks.active.ordered.map(&:block_type)).to eq([ "paragraph" ])
    expect(workflow_run.result_json.fetch("markdown")).to include("Created by the workflow executor.")
  end

  it "updates a nota from Markdown and returns the re-read document" do
    workspace, user = create_workspace_and_owner("update-nota")
    page = workspace.pages.create!(title: "Old title", created_by: user)
    page.blocks.create!(
      workspace: workspace,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Old body" } ] } ]
      }
    )
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_UPDATE_NOTA,
      input: {
        "page_id" => page.id,
        "title" => "Updated title",
        "markdown" => "## New section\n\nUpdated body"
      }
    )

    described_class.new(workflow_run: workflow_run).call

    expect(workflow_run.reload).to be_succeeded
    expect(page.reload.title).to eq("Updated title")
    expect(page.blocks.active.ordered.map(&:block_type)).to eq(%w[heading_2 paragraph])
    expect(page.blocks.active.ordered.map(&:search_text).join(" ")).not_to include("Old body")
    expect(workflow_run.result_json.dig("page", "title")).to eq("Updated title")
    expect(workflow_run.result_json.fetch("markdown")).to include("Updated body")
  end

  it "leaves empty Nota fields unchanged and honors the requested body mode" do
    workspace, user = create_workspace_and_owner("update-nota-fields")
    page = workspace.pages.create!(title: "Keep this title", created_by: user)
    page.blocks.create!(
      workspace: workspace,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [ { "type" => "paragraph", "content" => [ { "type" => "text", "text" => "Keep this body" } ] } ]
      }
    )
    keep_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_UPDATE_NOTA,
      input: { "page_id" => page.id, "title" => "", "body" => "", "body_mode" => "keep" }
    )
    append_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_UPDATE_NOTA,
      input: { "page_id" => page.id, "title" => "", "body" => "Appended body", "body_mode" => "append" }
    )

    described_class.new(workflow_run: keep_run).call
    described_class.new(workflow_run: append_run).call

    expect(keep_run.reload).to be_succeeded
    expect(append_run.reload).to be_succeeded
    expect(page.reload.title).to eq("Keep this title")
    markdown = Pages::MarkdownExportService.call(page: page).markdown
    expect(markdown).to include("Keep this body")
    expect(markdown).to include("Appended body")
  end

  it "creates a generic database with a linked page, table view, properties, rows, and cells" do
    workspace, user = create_workspace_and_owner("create-database")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_DATABASE,
      input: {
        "name" => "Launch tracker",
        "description" => "A general release database",
        "properties" => [
          { "name" => "Owner", "type" => "text" },
          { "name" => "Due", "property_type" => "date" },
          { "name" => "Stage", "type" => "select", "options" => [ "Draft", "Ready" ] }
        ],
        "rows" => [
          {
            "title" => "Prepare release",
            "cells" => [
              { "property" => "owner", "value" => "Taylor" },
              { "property" => "DUE", "value" => "2026-07-20" },
              { "property" => "Stage", "value" => "Draft" }
            ]
          }
        ]
      }
    )

    described_class.new(workflow_run: workflow_run).call

    expect(workflow_run.reload).to be_succeeded
    database = Database.find(workflow_run.result_json.fetch("target_id"))
    expect(database.linked_page).to be_present
    expect(database.linked_page.title).to eq("Launch tracker")
    expect(database.description).to eq("A general release database")
    expect(database.database_views.pluck(:name, :view_type, :default)).to eq([ [ "Table", "table", true ] ])
    expect(database.db_properties.ordered.pluck(:name, :property_type)).to eq(
      [ [ "Owner", "text" ], [ "Due", "date" ], [ "Stage", "select" ] ]
    )
    row = database.db_rows.find_by!(title: "Prepare release")
    expect(row.reload.data_json.slice("Owner", "Due", "Stage")).to eq(
      "Owner" => "Taylor",
      "Due" => "2026-07-20",
      "Stage" => "Draft"
    )
    expect(workflow_run.result_json.dig("database", "linked_page", "id")).to eq(database.linked_page_id)
  end

  it "applies explicit task cells by exact case-insensitive property name before fallbacks" do
    workspace, user = create_workspace_and_owner("task-cells")
    database = workspace.databases.create!(name: "Tasks", created_by: user)
    database.db_properties.create!(name: "Owner", property_type: :text)
    database.db_properties.create!(name: "Due", property_type: :date)
    database.db_properties.create!(name: "Notes", property_type: :text)
    database.db_properties.create!(name: "Status", property_type: :select)
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_TASK,
      input: {
        "database_id" => database.id,
        "title" => "Ship release",
        "owner_name" => "Fallback owner",
        "due_on" => "2026-07-21",
        "body" => "Fallback notes",
        "cells" => [ { "property" => "oWnEr", "value" => "Explicit owner" } ]
      }
    )

    described_class.new(workflow_run: workflow_run).call

    row = database.db_rows.find(workflow_run.reload.result_json.fetch("target_id"))
    expect(row.data_json.slice("Owner", "Due", "Notes", "Status")).to eq(
      "Owner" => "Explicit owner",
      "Due" => "2026-07-21",
      "Notes" => "Fallback notes",
      "Status" => "not started"
    )
  end

  it "allows writable provider calendars and queues their sync" do
    workspace, user = create_workspace_and_owner("provider-calendar")
    connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "google",
      label: "Workflow Google",
      access_token: "token"
    )
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: connection,
      created_by: user,
      provider: "google",
      remote_id: "primary",
      name: "Primary",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "provider",
      read_only: false,
      enabled: true
    )
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_CALENDAR_EVENT,
      input: {
        "kalendarium_calendar_id" => calendar.id,
        "title" => "Workflow event",
        "starts_at" => "2026-07-20 09:00",
        "ends_at" => "2026-07-20 10:00",
        "time_zone" => "Australia/Melbourne"
      }
    )

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.to have_enqueued_job(Kalendarium::SyncCalendarJob).with(calendar.id)

    expect(workflow_run.reload).to be_succeeded
    event = KalendariumEvent.find(workflow_run.result_json.fetch("target_id"))
    expect(event.kalendarium_calendar).to eq(calendar)
    expect(event.starts_at_utc).to eq(Time.zone.parse("2026-07-19 23:00:00 UTC"))
    expect(workflow_run.result_json.fetch("url")).to include("date=2026-07-20")
    expect(Kalendarium::SyncCalendarJob.enqueue_after_transaction_commit).to eq(true)
  end

  it "rolls back all action writes when the workflow cannot be marked succeeded" do
    workspace, user = create_workspace_and_owner("atomic-action")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_DATABASE,
      max_attempts: 1,
      input: {
        "name" => "Should roll back",
        "properties" => [ { "name" => "Owner", "type" => "text" } ],
        "rows" => [
          { "title" => "Invalid", "cells" => [ { "property" => "Missing", "value" => "value" } ] }
        ]
      }
    )

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.not_to change(Database, :count)

    expect(workflow_run.reload).to be_failed
    expect(workflow_run.error_message).to include("Unknown database property")
  end

  it "blocks writes when the launching actor loses authorization before execution" do
    workspace, user = create_workspace_and_owner("reauthorize")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_NOTA,
      max_attempts: 1,
      input: { "title" => "Unauthorized", "body" => "Must not be created" }
    )
    Membership.find_by!(workspace: workspace, user: user).destroy!

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.not_to change(Page, :count)

    expect(workflow_run.reload).to be_failed
    expect(workflow_run.error_message).to include("not allowed")
  end

  it "does not repeat a finished action when execution is retried" do
    workspace, user = create_workspace_and_owner("finished-retry")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_NOTA,
      input: { "title" => "Only once", "body" => "One page only" }
    )

    expect do
      described_class.new(workflow_run: workflow_run).call
      described_class.new(workflow_run: workflow_run.reload).call
    end.to change(Page, :count).by(1)

    expect(workflow_run.reload.attempts_count).to eq(1)
  end

  it "reclaims a running workflow after its execution lease expires" do
    workspace, user = create_workspace_and_owner("stale-running")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_NOTA,
      max_attempts: 2,
      input: { "title" => "Recovered", "body" => "Recovered after worker loss" }
    )
    workflow_run.update!(
      status: WorkflowRun::STATUS_RUNNING,
      attempts_count: 1,
      started_at: 20.minutes.ago,
      metadata_json: { "attempt_claimed_at" => 20.minutes.ago.iso8601 }
    )

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.to change(Page, :count).by(1)

    expect(workflow_run.reload).to be_succeeded
    expect(workflow_run.attempts_count).to eq(2)
  end

  it "schedules a lease check when a running workflow is redelivered too soon" do
    workspace, user = create_workspace_and_owner("fresh-running")
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_NOTA,
      max_attempts: 2,
      input: { "title" => "Wait", "body" => "The original worker may still be active" }
    )
    workflow_run.update!(
      status: WorkflowRun::STATUS_RUNNING,
      attempts_count: 1,
      started_at: Time.current,
      metadata_json: { "attempt_claimed_at" => Time.current.iso8601 }
    )
    original_page_count = Page.count

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.to have_enqueued_job(Workflows::ExecuteRunJob).with(workflow_run.id)

    expect(workflow_run.reload).to be_running
    expect(Page.count).to eq(original_page_count)
  end

  it "re-checks the database lock immediately before creating a row" do
    workspace, user = create_workspace_and_owner("locked-action")
    database = workspace.databases.create!(name: "Locked after launch", created_by: user, locked: true)
    workflow_run = create_run(
      workspace: workspace,
      user: user,
      kind: WorkflowRun::KIND_CREATE_TASK,
      input: { "database_id" => database.id, "title" => "Blocked row" }
    )

    expect do
      described_class.new(workflow_run: workflow_run).call
    end.not_to change(DbRow, :count)

    expect(workflow_run.reload).to be_failed
    expect(workflow_run.error_message).to include("Grid is locked")
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

  def create_workspace_and_owner(suffix)
    workspace = Workspace.create!(name: "Workflow #{suffix.titleize}", slug: "workflow-#{suffix}")
    user = User.create!(email: "workflow-#{suffix}@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    [ workspace, user ]
  end

  def create_run(workspace:, user:, kind:, input:, max_attempts: 1)
    WorkflowRun.create!(
      workspace: workspace,
      user: user,
      workflow_kind: kind,
      status: WorkflowRun::STATUS_QUEUED,
      trigger_source: "ai_assistant",
      queued_at: Time.current,
      max_attempts: max_attempts,
      confidence_score: 1.0,
      input_json: input
    )
  end
end
