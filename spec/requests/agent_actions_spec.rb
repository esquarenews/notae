require "rails_helper"

RSpec.describe "Agent actions", type: :request do
  let(:workspace) { Workspace.create!(name: "Agent Actions", slug: "agent-actions") }
  let(:member) { User.create!(email: "agent-actions-member@example.com", password: "password123") }
  let(:owner) { User.create!(email: "agent-actions-owner@example.com", password: "password123") }

  before do
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
  end

  it "creates a pending email draft with review history" do
    sign_in member

    post agent_actions_path(workspace_slug: workspace.slug), params: {
      agent_action: {
        title: "Draft launch email",
        target_system: "gmail",
        draft_type: "email_draft",
        to_line: "team@example.com\nops@example.com",
        cc_line: "manager@example.com",
        subject: "Launch review",
        body: "Please review before sending."
      }
    }

    agent_action = AgentAction.order(:created_at).last

    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.title).to eq("Draft launch email")
    expect(agent_action.status).to eq(AgentAction::STATUS_PENDING)
    expect(agent_action.payload_json.fetch("to")).to eq([ "team@example.com", "ops@example.com" ])
    expect(agent_action.payload_json.fetch("cc")).to eq([ "manager@example.com" ])
    expect(agent_action.payload_json.fetch("subject")).to eq("Launch review")
    expect(agent_action.review_history.pluck(:event_type)).to eq(%w[policy_evaluated draft_created])
  end

  it "updates a pending draft and keeps the revision comment in history" do
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
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

    sign_in member

    patch agent_action_path(workspace_slug: workspace.slug, id: agent_action.id), params: {
      agent_action: {
        title: "Draft issue comment v2",
        target_system: "github",
        draft_type: "github_comment_draft",
        repository: "org/repo",
        target_reference: "#42",
        body: "Updated comment.",
        revision_comment: "Tone down the certainty."
      }
    }

    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.reload.title).to eq("Draft issue comment v2")
    expect(agent_action.payload_json.fetch("body")).to eq("Updated comment.")
    expect(agent_action.review_history.find_by!(event_type: "draft_updated").comment).to eq("Tone down the certainty.")
  end

  it "approves a calendar draft into a selected calendar and shows the execution result afterwards" do
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Team Calendar",
      color_hex: "#2563EB",
      time_zone: "Australia/Melbourne",
      source_kind: "local",
      enabled: true
    )
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Hold calendar slot",
        proposed_by: "manual",
        target_system: "calendar",
        draft_type: "calendar_hold",
        payload_json: {
          "title" => "Customer review",
          "starts_at" => "2026-03-20T09:00",
          "ends_at" => "2026-03-20T09:30",
          "attendees" => [ "team@example.com" ],
          "body" => "Review the agenda."
        }
      }
    ).call

    sign_in owner

    post approve_agent_action_path(workspace_slug: workspace.slug, id: agent_action.id), params: {
      destination_calendar_id: calendar.id,
      decision_comment: "Approved and scheduled."
    }

    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.reload.status).to eq(AgentAction::STATUS_APPROVED)
    expect(agent_action.dry_run).to be(false)
    expect(agent_action.result_json.fetch("dry_run")).to eq(false)
    expect(agent_action.result_json.fetch("summary")).to eq("Created event in Team Calendar.")
    created_event = KalendariumEvent.find(agent_action.result_json.fetch("target_id"))
    expect(created_event.kalendarium_calendar).to eq(calendar)
    expect(agent_action.review_history.find_by!(event_type: "approved").comment).to eq("Approved and scheduled.")

    get agent_action_path(workspace_slug: workspace.slug, id: agent_action.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("This draft is now read-only.")
    expect(response.body).to include("Execution result")
    expect(response.body).to include("Created event in Team Calendar.")
    expect(response.body).to include("Open created item")
  end

  it "asks approvers to choose a destination task list or calendar before approval" do
    database = Database.create!(workspace: workspace, name: "Task Inbox", created_by: owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: owner,
      name: "Ops Calendar",
      color_hex: "#059669",
      time_zone: "Australia/Melbourne",
      source_kind: "local",
      enabled: true
    )
    task_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft CRM ticket",
        proposed_by: "manual",
        target_system: "crm",
        draft_type: "task_ticket",
        payload_json: {
          "project" => "Inbox",
          "title" => "Follow up contract",
          "body" => "Call the customer tomorrow."
        }
      }
    ).call
    calendar_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Hold discovery call",
        proposed_by: "manual",
        target_system: "calendar",
        draft_type: "calendar_hold",
        payload_json: {
          "title" => "Discovery call",
          "starts_at" => "2026-03-20T10:00",
          "ends_at" => "2026-03-20T10:30",
          "attendees" => [],
          "body" => "Discuss the open questions."
        }
      }
    ).call

    sign_in owner

    get agent_action_path(workspace_slug: workspace.slug, id: task_action.id)
    expect(response.body).to include("Save to task list")
    expect(response.body).to include(database.name)

    get agent_action_path(workspace_slug: workspace.slug, id: calendar_action.id)
    expect(response.body).to include("Save to calendar")
    expect(response.body).to include(calendar.name)

    post approve_agent_action_path(workspace_slug: workspace.slug, id: calendar_action.id), params: {
      decision_comment: "Missing destination should fail."
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Select a calendar before approving.")
  end

  it "rejects a draft and records the decision comment" do
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft CRM ticket",
        proposed_by: "manual",
        target_system: "crm",
        draft_type: "task_ticket",
        payload_json: {
          "project" => "Customer Ops",
          "title" => "Follow up contract",
          "body" => "Call the customer tomorrow."
        }
      }
    ).call

    sign_in owner

    post reject_agent_action_path(workspace_slug: workspace.slug, id: agent_action.id), params: {
      decision_comment: "Need finance input before this is queued."
    }

    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.reload.status).to eq(AgentAction::STATUS_REJECTED)
    expect(agent_action.review_history.find_by!(event_type: "rejected").comment).to eq("Need finance input before this is queued.")
  end

  it "supports request-changes and resubmission without terminal rejection" do
    agent_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft partner update",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "partner@example.com" ],
          "cc" => [],
          "subject" => "Status update",
          "body" => "Initial draft."
        }
      }
    ).call

    sign_in owner
    post request_changes_agent_action_path(workspace_slug: workspace.slug, id: agent_action.id), params: {
      decision_comment: "Add revised timing and next steps."
    }
    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    expect(agent_action.reload.status).to eq(AgentAction::STATUS_CHANGES_REQUESTED)

    sign_out owner
    sign_in member
    patch agent_action_path(workspace_slug: workspace.slug, id: agent_action.id), params: {
      agent_action: {
        title: "Draft partner update v2",
        target_system: "gmail",
        draft_type: "email_draft",
        to_line: "partner@example.com",
        subject: "Status update",
        body: "Updated with revised timing and next steps.",
        revision_comment: "Added the requested timing detail."
      }
    }

    expect(response).to redirect_to(agent_action_path(workspace_slug: workspace.slug, id: agent_action.id))
    agent_action.reload
    expect(agent_action.status).to eq(AgentAction::STATUS_PENDING)
    expect(agent_action.review_history.pluck(:event_type)).to include("changes_requested", "resubmitted")
  end

  it "shows approval inbox and revision queue sections on the index page" do
    pending = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Pending review",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [],
          "subject" => "Pending",
          "body" => "Needs approval."
        }
      }
    ).call
    needs_revision = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Needs revision",
        proposed_by: "manual",
        target_system: "gmail",
        draft_type: "email_draft",
        payload_json: {
          "to" => [ "team@example.com" ],
          "cc" => [],
          "subject" => "Revision",
          "body" => "Needs changes."
        }
      }
    ).call
    AgentActions::RequestChangesService.new(agent_action: needs_revision, actor: owner, comment: "Revise this").call

    sign_in owner
    get agent_actions_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Pending approvals")
    expect(response.body).to include(pending.title)

    sign_out owner
    sign_in member
    get agent_actions_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Needs your revision")
    expect(response.body).to include(needs_revision.title)
  end
end
