require "rails_helper"

RSpec.describe "API V1 Meetings sessions", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "returns workspace-scoped meeting sessions and transcript payload" do
    user = User.create!(email: "api-meetings-owner@example.com", password: "password123")
    outsider = User.create!(email: "api-meetings-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "API meetings", slug: "api-meetings")
    other_workspace = Workspace.create!(name: "API meetings other", slug: "api-meetings-other")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: outsider, role: :owner)

    session = MeetingSession.create!(
      workspace: workspace,
      title: "API meeting session",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      transcript_text: "[00:00] Alex: Hello",
      created_by: user,
      updated_by: user
    )
    session.meeting_utterances.create!(
      position: 0,
      speaker_key: "S1",
      speaker_name: "Alex",
      text: "Hello everyone"
    )

    MeetingSession.create!(
      workspace: other_workspace,
      title: "Other workspace session",
      capture_mode: "upload",
      provider: "local",
      status: "completed",
      created_by: outsider,
      updated_by: outsider
    )

    token = ApiToken.create!(user: user, name: "Meetings API token")

    get "/api/v1/workspaces/#{workspace.slug}/meetings/sessions", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    ids = json_body.fetch("data").map { |row| row.fetch("id") }
    expect(ids).to eq([session.id])

    get "/api/v1/workspaces/#{workspace.slug}/meetings/sessions/#{session.id}/transcript", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    transcript_payload = json_body.fetch("data")
    expect(transcript_payload.fetch("id")).to eq(session.id)
    expect(transcript_payload.fetch("transcript_text")).to include("Alex")
    expect(transcript_payload.fetch("utterances").first.fetch("speaker_name")).to eq("Alex")
  end
end
