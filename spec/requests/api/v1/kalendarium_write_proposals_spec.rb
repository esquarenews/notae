require "rails_helper"

RSpec.describe "API V1 Kalendarium write proposals", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  def build_stack(suffix:)
    user = User.create!(email: "api-kal-proposal-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Kal Proposal #{suffix}", slug: "api-kal-proposal-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    token = ApiToken.create!(user: user, name: "Kal proposal token")

    [ user, workspace, calendar, token ]
  end

  it "creates and confirms a write proposal" do
    user, workspace, calendar, token = build_stack(suffix: "confirm")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/write_proposals",
         params: {
           kalendarium_write_proposal: {
             operation: "create",
             proposed_by: "api",
             payload_json: {
               kalendarium_calendar_id: calendar.id,
               title: "Proposal event",
               starts_at_utc: "2026-03-03T09:00:00Z",
               ends_at_utc: "2026-03-03T10:00:00Z"
             }
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    proposal_id = json_body.dig("data", "id")
    proposal = KalendariumWriteProposal.find(proposal_id)
    expect(proposal.status).to eq("pending")

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/write_proposals/#{proposal_id}/confirm",
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:ok)
    expect(proposal.reload.status).to eq("confirmed")
    expect(proposal.kalendarium_event).to be_present
    expect(proposal.kalendarium_event.title).to eq("Proposal event")
    expect(proposal.user).to eq(user)
  end

  it "rejects a pending write proposal" do
    user, workspace, calendar, token = build_stack(suffix: "reject")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Existing",
      starts_at_utc: 1.day.from_now,
      ends_at_utc: 1.day.from_now + 1.hour,
      created_by: user,
      updated_by: user,
      reminder_offsets_minutes: [ 10 ]
    )
    proposal = KalendariumWriteProposal.create!(
      workspace: workspace,
      user: user,
      proposed_by: "api",
      operation: "update",
      status: "pending",
      kalendarium_event: event,
      payload_json: { id: event.id, title: "Changed" }
    )

    post "/api/v1/workspaces/#{workspace.slug}/kalendarium/write_proposals/#{proposal.id}/reject",
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:ok)
    expect(proposal.reload.status).to eq("rejected")
    expect(proposal.rejected_at).to be_present
  end
end
