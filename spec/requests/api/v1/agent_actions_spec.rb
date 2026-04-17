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
    expect(created_row.database).to eq(database)
    expect(payload.fetch("review_history").map { |entry| entry.fetch("event_type") }).to include("approved")
  end
end
