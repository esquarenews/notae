require "rails_helper"

RSpec.describe "API V1 Agent actions", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "creates and lists agent action drafts over the API" do
    member = User.create!(email: "api-agent-actions-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Agent Actions", slug: "api-agent-actions")
    Membership.create!(workspace: workspace, user: member, role: :member)
    token = ApiToken.create!(user: member, name: "Agent draft token")

    post "/api/v1/workspaces/#{workspace.slug}/agent_actions",
         params: {
           agent_action: {
             title: "Draft roadmap note",
             target_system: "notae",
             draft_type: "nota_draft",
             payload_json: {
               title: "Roadmap note",
               body: "Capture the rollout sequence."
             }
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    payload = json_body.fetch("data")
    expect(payload.fetch("status")).to eq("pending")
    expect(payload.fetch("proposed_by")).to eq("api")
    expect(payload.dig("preview_json", "mode")).to eq("create")
    expect(payload.dig("preview_json", "changes")).to include(
      a_hash_including("key" => "title", "after" => "Draft roadmap note")
    )
    expect(payload.fetch("review_history").map { |entry| entry.fetch("event_type") }).to eq(%w[policy_evaluated draft_created])

    get "/api/v1/workspaces/#{workspace.slug}/agent_actions", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    expect(json_body.fetch("data").map { |entry| entry.fetch("id") }).to include(payload.fetch("id"))
  end

  it "approves a task draft into a selected task list over the API" do
    member = User.create!(email: "api-agent-actions-task-member@example.com", password: "password123")
    owner = User.create!(email: "api-agent-actions-task-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Agent Actions Task", slug: "api-agent-actions-task")
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task Inbox", created_by: owner)
    task_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft task",
        proposed_by: "api",
        target_system: "crm",
        draft_type: "task_ticket",
        payload_json: {
          "project" => "Task Inbox",
          "title" => "Follow up",
          "body" => "Contact the customer."
        }
      }
    ).call
    token = ApiToken.create!(user: owner, name: "Agent approval token")

    post "/api/v1/workspaces/#{workspace.slug}/agent_actions/#{task_action.id}/approve",
         params: { destination_database_id: database.id, decision_comment: "Ship it." },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    created_row = DbRow.find(payload.dig("result_json", "target_id"))

    expect(payload.fetch("status")).to eq("approved")
    expect(payload.dig("result_json", "summary")).to eq("Created task in Task Inbox.")
    expect(payload.dig("result_json", "execution_preview", "changes")).to include(
      a_hash_including("label" => "Draft title", "after" => "Follow up"),
      a_hash_including("label" => "Project / Queue", "after" => "Task Inbox")
    )
    expect(created_row.database).to eq(database)
    expect(payload.fetch("review_history").map { |entry| entry.fetch("event_type") }).to include("approved")
  end

  it "reverses an approved task draft over the API" do
    member = User.create!(email: "api-agent-actions-reverse-member@example.com", password: "password123")
    owner = User.create!(email: "api-agent-actions-reverse-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Agent Actions Reverse", slug: "api-agent-actions-reverse")
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    database = Database.create!(workspace: workspace, name: "Task Inbox", created_by: owner)
    task_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Draft task",
        proposed_by: "api",
        target_system: "crm",
        draft_type: "task_ticket",
        payload_json: {
          "project" => "Task Inbox",
          "title" => "Follow up",
          "body" => "Contact the customer."
        }
      }
    ).call
    AgentActions::ApprovalService.new(
      agent_action: task_action,
      actor: owner,
      comment: "Approved.",
      destination_database_id: database.id
    ).call
    created_row = DbRow.find(task_action.reload.result_json.fetch("target_id"))
    token = ApiToken.create!(user: owner, name: "Agent reversal token")

    post "/api/v1/workspaces/#{workspace.slug}/agent_actions/#{task_action.id}/reverse",
         params: { decision_comment: "Ticket created in the wrong list." },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")
    expect(payload.fetch("reversed")).to eq(true)
    expect(payload.fetch("reversible")).to eq(false)
    expect(payload.dig("result_json", "reversal", "summary")).to eq("Archived the created task.")
    expect(created_row.reload.archived?).to eq(true)
    expect(payload.fetch("review_history").map { |entry| entry.fetch("event_type") }).to include("reversed")
  end

  it "rejects approvals into calendars the approver cannot update over the API" do
    member = User.create!(email: "api-agent-actions-calendar-member@example.com", password: "password123")
    owner = User.create!(email: "api-agent-actions-calendar-owner@example.com", password: "password123")
    private_calendar_owner = User.create!(email: "api-agent-actions-calendar-private-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Agent Actions Calendar", slug: "api-agent-actions-calendar")
    Membership.create!(workspace: workspace, user: member, role: :member)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: private_calendar_owner, role: :member)
    private_connection = KalendariumConnection.create!(
      workspace: workspace,
      owner: private_calendar_owner,
      created_by: private_calendar_owner,
      label: "Private Google",
      provider: "google",
      status: "connected",
      refresh_token: "token"
    )
    blocked_calendar = KalendariumCalendar.create!(
      workspace: workspace,
      kalendarium_connection: private_connection,
      created_by: private_calendar_owner,
      name: "Family and kids",
      color_hex: "#7C3AED",
      time_zone: "Australia/Melbourne",
      source_kind: "provider",
      provider: "google",
      enabled: true,
      read_only: false
    )
    calendar_action = AgentActions::DraftCreator.new(
      workspace: workspace,
      actor: member,
      attributes: {
        title: "Hold calendar slot",
        proposed_by: "api",
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
    token = ApiToken.create!(user: owner, name: "Agent approval blocked calendar token")

    post "/api/v1/workspaces/#{workspace.slug}/agent_actions/#{calendar_action.id}/approve",
         params: { destination_calendar_id: blocked_calendar.id, decision_comment: "Should fail." },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_body.fetch("error").fetch("message")).to eq("Selected calendar could not be found.")
  end
end
