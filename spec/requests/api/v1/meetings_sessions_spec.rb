require "rails_helper"

RSpec.describe "API V1 Meetings sessions", type: :request do
  include ActiveJob::TestHelper

  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  before do
    clear_enqueued_jobs
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
    expect(ids).to eq([ session.id ])

    get "/api/v1/workspaces/#{workspace.slug}/meetings/sessions/#{session.id}/transcript", headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    transcript_payload = json_body.fetch("data")
    expect(transcript_payload.fetch("id")).to eq(session.id)
    expect(transcript_payload.fetch("transcript_text")).to include("Alex")
    expect(transcript_payload.fetch("utterances").first.fetch("speaker_name")).to eq("Alex")
  end

  it "creates a browser extension session, matches the preferred event, ingests transcript text, and exposes extension CORS headers" do
    user = User.create!(email: "api-meetings-extension@example.com", password: "password123")
    workspace = Workspace.create!(name: "API meetings extension", slug: "api-meetings-extension")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    preferred_event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Quarterly review",
      starts_at_utc: 15.minutes.from_now,
      ends_at_utc: 75.minutes.from_now,
      meeting_capture_enabled: true,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/ext-api-test" }
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Quarterly review backup",
      starts_at_utc: 25.minutes.from_now,
      ends_at_utc: 85.minutes.from_now,
      meeting_capture_enabled: false,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/ext-api-test" }
    )
    token = ApiToken.create!(user: user, name: "Meetings extension API token")

    options "/api/v1/workspaces/#{workspace.slug}/meetings/sessions", headers: {
      "Origin" => "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "Access-Control-Request-Method" => "POST",
      "Access-Control-Request-Headers" => "authorization,content-type"
    }

    expect(response.headers["Access-Control-Allow-Origin"]).to eq("chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    expect(response.headers["Access-Control-Allow-Methods"]).to include("POST")

    post "/api/v1/workspaces/#{workspace.slug}/meetings/sessions",
         params: {
           meeting_session: {
             title: "Quarterly review",
             join_url: "https://meet.google.com/ext-api-test"
           }
         }.to_json,
         headers: auth_headers(token).merge(
           "Content-Type" => "application/json",
           "Origin" => "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
         )

    expect(response).to have_http_status(:created)
    payload = json_body.fetch("data")
    session = MeetingSession.find(payload.fetch("id"))

    expect(session.capture_mode).to eq("browser_extension")
    expect(session.provider).to eq("google_meet")
    expect(session.status).to eq("recording")
    expect(session.kalendarium_event_id).to eq(preferred_event.id)
    expect(session.page).to be_present
    expect(payload.fetch("capture_mode_label")).to eq("Google Meet extension")
    expect(payload.fetch("page_path")).to eq("/w/#{workspace.slug}/pages/#{session.page_id}")

    post "/api/v1/workspaces/#{workspace.slug}/meetings/sessions/#{session.id}/ingest_transcript",
         params: {
           meeting_session: {
             utterances: [
               {
                 speaker_key: "S1",
                 speaker_name: "Errol",
                 text: "Welcome to the review",
                 started_ms: 0,
                 ended_ms: 1200,
                 confidence: 0.9
               }
             ],
             metadata: {
               source_language: "en"
             }
           }
         }.to_json,
         headers: auth_headers(token).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:ok)
    expect(session.reload.status).to eq("summarizing")
    expect(session.transcript_text).to include("Errol: Welcome to the review")
    expect(session.metadata_json["transcript_source"]).to eq("google_meet_extension")
    expect(session.metadata_json["capture_origin"]).to eq("chrome_extension")
    expect(session.metadata_json["source_language"]).to eq("en")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::SummarizeSessionJob)
  end

  it "cancels a browser extension session when no transcript was captured" do
    user = User.create!(email: "api-meetings-extension-cancel@example.com", password: "password123")
    workspace = Workspace.create!(name: "API meetings extension cancel", slug: "api-meetings-extension-cancel")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "No captions meeting",
      capture_mode: "browser_extension",
      provider: "google_meet",
      status: "recording",
      created_by: user,
      updated_by: user
    )
    token = ApiToken.create!(user: user, name: "Meetings extension cancel token")

    post "/api/v1/workspaces/#{workspace.slug}/meetings/sessions/#{session.id}/cancel",
         headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    expect(session.reload.status).to eq("cancelled")
    expect(session.error_message).to eq("Cancelled from Google Meet extension.")
  end
end
