require "rails_helper"

RSpec.describe Meetings::AutoStopSessionJob, type: :job do
  include ActiveJob::TestHelper

  def build_stack(suffix:)
    user = User.create!(email: "meeting-auto-stop-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Auto Stop Job #{suffix}", slug: "meeting-auto-stop-job-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Main",
      color_hex: "#3B82F6",
      time_zone: "UTC",
      source_kind: "local"
    )

    [ user, workspace, calendar ]
  end

  before do
    clear_enqueued_jobs
  end

  it "auto-stops a due recording session and marks the active run failed" do
    user, workspace, calendar = build_stack(suffix: "due")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Ended event",
      starts_at_utc: 1.hour.ago,
      ends_at_utc: 5.minutes.ago,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/auto-stop-due" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Recording session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "recording",
      join_url: event.meeting_join_url
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording"
    )

    described_class.perform_now(session.id)

    expect(session.reload.status).to eq("cancelled")
    expect(run.reload.status).to eq("failed")
  end

  it "re-enqueues itself when the session end time is still in the future" do
    user, workspace, calendar = build_stack(suffix: "future")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Still running later",
      starts_at_utc: 10.minutes.from_now,
      ends_at_utc: 2.hours.from_now,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/auto-stop-future" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Future stop session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "joining",
      join_url: event.meeting_join_url
    )

    described_class.perform_now(session.id)

    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::AutoStopSessionJob)
    expect(session.reload.status).to eq("joining")
  end
end
