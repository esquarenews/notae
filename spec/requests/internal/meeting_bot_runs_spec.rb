require "rails_helper"

RSpec.describe "Internal meeting bot runs", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    original = ENV["MEETING_BOT_INTERNAL_TOKEN"]
    ENV["MEETING_BOT_INTERNAL_TOKEN"] = "internal-token"
    clear_enqueued_jobs
    example.run
  ensure
    ENV["MEETING_BOT_INTERNAL_TOKEN"] = original
    clear_enqueued_jobs
  end

  def headers
    { "Authorization" => "Bearer internal-token", "Accept" => "application/json" }
  end

  it "claims queued runs and accepts upload completion" do
    user = User.create!(email: "internal-bot-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Internal bot", slug: "internal-bot")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "Bot capture session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: "https://meet.google.com/abc-defg-hij",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "queued"
    )

    post "/internal/meeting_bot_runs/claim", params: { worker_id: "worker-1" }, headers: headers
    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload.dig("data", "id")).to eq(run.id)
    expect(payload.dig("data", "transcript_complete_path")).to eq("/internal/meeting_bot_runs/#{run.id}/transcript_complete")
    expect(run.reload.status).to eq("claimed")

    Tempfile.create([ "meeting-upload", ".webm" ]) do |file|
      file.binmode
      file.write("fake-media")
      file.flush
      uploaded = Rack::Test::UploadedFile.new(file.path, "audio/webm")

      post "/internal/meeting_bot_runs/#{run.id}/upload_complete",
           params: { file: uploaded },
           headers: headers
    end

    expect(response).to have_http_status(:ok)
    expect(run.reload.status).to eq("finished")
    expect(session.reload.capture_files).to be_attached
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::ProcessSessionJob)
  end

  it "syncs meeting session status from worker heartbeat updates" do
    user = User.create!(email: "internal-bot-heartbeat@example.com", password: "password123")
    workspace = Workspace.create!(name: "Internal bot heartbeat", slug: "internal-bot-heartbeat")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "Heartbeat session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: "https://meet.google.com/heartbeat-test",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "claimed",
      worker_id: "worker-heartbeat",
      claimed_at: Time.current
    )

    post "/internal/meeting_bot_runs/#{run.id}/heartbeat",
         params: { status: "recording", worker_id: "worker-heartbeat" },
         headers: headers

    expect(response).to have_http_status(:ok)
    expect(run.reload.status).to eq("recording")
    session.reload
    expect(session.status).to eq("recording")
    expect(session.started_at).to be_present
  end

  it "returns continue false when the session has been cancelled" do
    user = User.create!(email: "internal-bot-stop@example.com", password: "password123")
    workspace = Workspace.create!(name: "Internal bot stop", slug: "internal-bot-stop")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "Stop session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "cancelled",
      join_url: "https://meet.google.com/stop-session-test",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording",
      worker_id: "worker-stop",
      claimed_at: Time.current
    )

    post "/internal/meeting_bot_runs/#{run.id}/heartbeat",
         params: { status: "recording", worker_id: "worker-stop" },
         headers: headers

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)).to include("continue" => false)
    expect(run.reload.status).to eq("recording")
  end

  it "accepts transcript completion from the worker and queues summarization" do
    user = User.create!(email: "internal-bot-transcript@example.com", password: "password123")
    workspace = Workspace.create!(name: "Internal bot transcript", slug: "internal-bot-transcript")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Transcript event",
      starts_at_utc: 30.minutes.ago,
      ends_at_utc: 5.minutes.ago
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Transcript session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "recording",
      join_url: "https://meet.google.com/transcript-session-test",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording",
      worker_id: "worker-transcript",
      claimed_at: Time.current
    )

    post "/internal/meeting_bot_runs/#{run.id}/transcript_complete",
         params: {
           transcript_text: "Errol: Welcome everyone",
           utterances: [
             {
               speaker_key: "S1",
               speaker_name: "Errol",
               text: "Welcome everyone",
               started_ms: 0,
               ended_ms: 1000,
               confidence: 0.9
             }
           ],
           metadata: {
             transcript_source: "meeting_bot_captions"
           }
         },
         headers: headers

    expect(response).to have_http_status(:ok)
    expect(run.reload.status).to eq("finished")
    session.reload
    expect(session.status).to eq("summarizing")
    expect(session.transcript_text).to include("Errol: Welcome everyone")
    expect(session.metadata_json["transcript_source"]).to eq("meeting_bot_captions")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::SummarizeSessionJob)
  end

  it "rejects non-media uploads" do
    user = User.create!(email: "internal-bot-invalid-upload@example.com", password: "password123")
    workspace = Workspace.create!(name: "Internal bot invalid upload", slug: "internal-bot-invalid-upload")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "Invalid upload session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: "https://meet.google.com/invalid-upload-test",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "claimed",
      worker_id: "worker-invalid",
      claimed_at: Time.current
    )

    Tempfile.create([ "meeting-upload", ".txt" ]) do |file|
      file.binmode
      file.write("not-media")
      file.flush
      uploaded = Rack::Test::UploadedFile.new(file.path, "text/plain")

      post "/internal/meeting_bot_runs/#{run.id}/upload_complete",
           params: { file: uploaded },
           headers: headers
    end

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).dig("error", "message")).to include("Only audio or video uploads are supported")
    expect(run.reload.status).to eq("claimed")
    expect(session.reload.capture_files).not_to be_attached
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Meetings::ProcessSessionJob)
  end
end
