require "rails_helper"

RSpec.describe AgentActions::ApprovalService do
  include ActiveJob::TestHelper

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "approves email drafts in dry-run mode and logs the decision trail" do
    workspace = Workspace.create!(name: "Approval Service", slug: "approval-service")
    author = User.create!(email: "approval-service-author@example.com", password: "password123")
    approver = User.create!(email: "approval-service-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Draft rollout note",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [ "approvals@example.com" ],
          "subject" => "Rollout note",
          "body" => "Please review the rollout."
        }
      }
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: approver,
      comment: "Looks safe to send once live adapters exist."
    ).call

    agent_action.reload

    expect(agent_action.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.approved_by).to eq(approver)
    expect(agent_action.approved_at).to be_present
    expect(agent_action.executed_at).to be_present
    expect(agent_action.dry_run).to be(true)
    expect(agent_action.result_json.fetch("dry_run")).to eq(true)
    expect(agent_action.result_json.fetch("target_system")).to eq("gmail")
    expect(agent_action.result_json.fetch("summary")).to include("No message was sent")

    expect(agent_action.review_history.pluck(:event_type)).to eq(
      %w[policy_evaluated draft_created policy_evaluated approved tool_used]
    )
    expect(agent_action.review_history.find_by!(event_type: "approved").comment).to eq("Looks safe to send once live adapters exist.")
    approval_notification = Notification.where(recipient: author, notifiable: agent_action).order(:created_at).last
    expect(approval_notification.notification_type).to eq(Notification::TYPE_AGENT_ACTION_APPROVED)

    audit_actions = AuditEvent.where(auditable: agent_action).order(:created_at).pluck(:action)
    expect(audit_actions).to include(
      "agent_action_policy_evaluated",
      "agent_action_draft_created",
      "agent_action_approved",
      "agent_action_tool_used"
    )
  end

  it "creates a real kalendarium event when an approved calendar draft selects a destination calendar" do
    workspace = Workspace.create!(name: "Approval Calendar", slug: "approval-calendar")
    author = User.create!(email: "approval-calendar-author@example.com", password: "password123")
    approver = User.create!(email: "approval-calendar-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: approver,
      name: "Ops Calendar",
      color_hex: "#2563EB",
      time_zone: "Australia/Melbourne",
      source_kind: "local",
      enabled: true
    )

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Hold customer review",
        proposed_by: "manual",
        target_system: "calendar",
        draft_type: "calendar_hold",
        payload_json: {
          "title" => "Customer review",
          "starts_at" => "2026-03-24T09:00:00+11:00",
          "ends_at" => "2026-03-24T09:30:00+11:00",
          "attendees" => [ "ops@example.com" ],
          "body" => "Review the updated agenda."
        }
      }
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: approver,
      destination_calendar_id: calendar.id
    ).call

    agent_action.reload
    created_event = KalendariumEvent.find(agent_action.result_json.fetch("target_id"))

    expect(agent_action.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.dry_run).to be(false)
    expect(agent_action.result_json.fetch("dry_run")).to eq(false)
    expect(agent_action.result_json.fetch("target_type")).to eq("KalendariumEvent")
    expect(agent_action.result_json.fetch("summary")).to eq("Created event in Ops Calendar.")
    expect(created_event.kalendarium_calendar).to eq(calendar)
    expect(created_event.title).to eq("Customer review")
    expect(created_event.description).to eq("Review the updated agenda.")
    expect(created_event.created_by).to eq(approver)
    expect(created_event.metadata_json.fetch("invitees")).to eq([ { "email" => "ops@example.com" } ])
  end

  it "creates a real grid row when an approved task draft selects a destination task list" do
    workspace = Workspace.create!(name: "Approval Tasks", slug: "approval-tasks")
    author = User.create!(email: "approval-tasks-author@example.com", password: "password123")
    approver = User.create!(email: "approval-tasks-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)
    database = Database.create!(workspace: workspace, name: "Action Items", created_by: approver)
    DbProperty.create!(workspace: workspace, database: database, name: "Assignee", property_type: :text)
    DbProperty.create!(workspace: workspace, database: database, name: "Due date", property_type: :date)
    DbProperty.create!(workspace: workspace, database: database, name: "Notes", property_type: :text)
    DbProperty.create!(workspace: workspace, database: database, name: "Queue", property_type: :text)
    DbProperty.create!(workspace: workspace, database: database, name: "Status", property_type: :select)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Create follow-up task",
        proposed_by: "manual",
        target_system: "crm",
        draft_type: "task_ticket",
        payload_json: {
          "project" => "Inbox",
          "assignee" => "Errol",
          "due_at" => "2026-03-25",
          "title" => "Follow up contract",
          "body" => "Call the customer about the revised terms."
        }
      }
    ).call

    described_class.new(
      agent_action: agent_action,
      actor: approver,
      destination_database_id: database.id
    ).call

    agent_action.reload
    created_row = DbRow.find(agent_action.result_json.fetch("target_id"))

    expect(agent_action.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.dry_run).to be(false)
    expect(agent_action.result_json.fetch("dry_run")).to eq(false)
    expect(agent_action.result_json.fetch("target_type")).to eq("DbRow")
    expect(agent_action.result_json.fetch("summary")).to eq("Created task in Action Items.")
    expect(created_row.database).to eq(database)
    expect(created_row.title).to eq("Follow up contract")
    expect(created_row.db_cells.joins(:db_property).find_by(db_properties: { name: "Assignee" }).value_text).to eq("Errol")
    expect(created_row.db_cells.joins(:db_property).find_by(db_properties: { name: "Due date" }).value_text).to eq("2026-03-25")
    expect(created_row.db_cells.joins(:db_property).find_by(db_properties: { name: "Notes" }).value_text).to eq("Call the customer about the revised terms.")
    expect(created_row.db_cells.joins(:db_property).find_by(db_properties: { name: "Queue" }).value_text).to eq("Inbox")
    expect(created_row.db_cells.joins(:db_property).find_by(db_properties: { name: "Status" }).value_text).to eq("not started")
  end

  it "creates a real Nota when an approved Notae draft is reviewed" do
    workspace = Workspace.create!(name: "Approval Nota", slug: "approval-nota")
    author = User.create!(email: "approval-nota-author@example.com", password: "password123")
    approver = User.create!(email: "approval-nota-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)

    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Create project brief",
        proposed_by: "manual",
        target_system: "notae",
        draft_type: "nota_draft",
        payload_json: {
          "title" => "Project brief",
          "body" => "Capture the scope, timing, and next actions."
        }
      }
    ).call

    described_class.new(agent_action: agent_action, actor: approver).call

    agent_action.reload
    created_page = Page.find(agent_action.result_json.fetch("target_id"))

    expect(agent_action.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.dry_run).to be(false)
    expect(agent_action.result_json.fetch("target_type")).to eq("Page")
    expect(agent_action.result_json.fetch("summary")).to eq("Created Nota in Approval Nota.")
    expect(created_page.title).to eq("Project brief")
    expect(created_page.page_kind).to eq("nota")
    expect(created_page.blocks.first.content_json.dig("content", 0, "content", 0, "text")).to eq("Capture the scope, timing, and next actions.")
  end

  it "requires a destination before approving task or calendar drafts" do
    workspace = Workspace.create!(name: "Approval Destinations", slug: "approval-destinations")
    author = User.create!(email: "approval-destinations-author@example.com", password: "password123")
    approver = User.create!(email: "approval-destinations-approver@example.com", password: "password123")
    Membership.create!(workspace: workspace, user: author, role: :member)
    Membership.create!(workspace: workspace, user: approver, role: :owner)
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: author,
      attributes: {
        title: "Hold planning session",
        proposed_by: "manual",
        target_system: "calendar",
        draft_type: "calendar_hold",
        payload_json: {
          "title" => "Planning session",
          "starts_at" => "2026-03-24T10:00:00+11:00",
          "ends_at" => "2026-03-24T10:30:00+11:00",
          "attendees" => [],
          "body" => "Prepare the priorities."
        }
      }
    ).call

    expect {
      described_class.new(agent_action: agent_action, actor: approver).call
    }.to raise_error(AgentActions::ApprovalService::Error, "Select a calendar before approving.")
  end
end
