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
    expect(JSON.parse(response.body).dig("data", "id")).to eq(run.id)
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
