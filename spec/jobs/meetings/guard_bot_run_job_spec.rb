require "rails_helper"

RSpec.describe Meetings::GuardBotRunJob, type: :job do
  include ActiveJob::TestHelper

  def build_stack(suffix:)
    user = User.create!(email: "meeting-guard-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Guard Job #{suffix}", slug: "meeting-guard-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    session = MeetingSession.create!(
      workspace: workspace,
      title: "Guard target",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: "https://meet.google.com/guard-target",
      created_by: user,
      updated_by: user
    )

    [user, workspace, session]
  end

  before do
    clear_enqueued_jobs
  end

  it "fails queued runs that are never claimed" do
    _, _, session = build_stack(suffix: "never-claimed")
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "queued",
      created_at: 3.minutes.ago
    )

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("failed")
    expect(session.reload.status).to eq("failed")
    expect(session.error_message).to include("did not claim")
  end

  it "fails long-running joining runs" do
    _, _, session = build_stack(suffix: "stuck-joining")
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "joining",
      worker_id: "worker-join",
      claimed_at: 13.minutes.ago,
      last_heartbeat_at: 30.seconds.ago
    )

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("failed")
    expect(session.reload.error_message).to include("could not join")
  end

  it "re-enqueues itself while the run is still healthy and active" do
    _, _, session = build_stack(suffix: "healthy")
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording",
      worker_id: "worker-ok",
      claimed_at: 2.minutes.ago,
      last_heartbeat_at: Time.current
    )

    described_class.perform_now(run.id)

    expect(run.reload.status).to eq("recording")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(described_class)
  end
end
