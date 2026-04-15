require "rails_helper"

RSpec.describe Meetings::ScheduleDueCapturesJob, type: :job do
  include ActiveJob::TestHelper

  def build_stack(suffix:)
    user = User.create!(email: "meeting-schedule-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Schedule Job #{suffix}", slug: "meeting-schedule-job-#{suffix}")
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

  it "does not dispatch due scheduled online sessions now that browser bot capture is retired" do
    user, workspace, calendar = build_stack(suffix: "due-dispatch")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Due event",
      starts_at_utc: 1.minute.ago,
      ends_at_utc: 29.minutes.from_now,
      meeting_capture_enabled: false,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/due-dispatch-test" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Due session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "scheduled",
      join_url: "https://meet.google.com/due-dispatch-test",
      created_by: user,
      updated_by: user
    )

    described_class.perform_now

    session.reload
    expect(session.status).to eq("scheduled")
    expect(session.meeting_bot_runs.active.count).to eq(0)
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Meetings::StartBotRunJob)
  end

  it "does not create browser bot sessions from events marked for meeting transcripts" do
    user, workspace, calendar = build_stack(suffix: "future-deferred")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Future event",
      starts_at_utc: 1.minute.ago,
      ends_at_utc: 29.minutes.from_now,
      meeting_capture_enabled: true,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/future-deferred-test" }
    )

    expect { described_class.perform_now }.not_to change(MeetingSession, :count)
    expect(event.reload.meeting_capture_enabled).to be(true)
  end

  it "auto-stops ended online sessions and marks active bot runs as failed" do
    user, workspace, calendar = build_stack(suffix: "auto-stop-ended")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Ended event",
      starts_at_utc: 2.hours.ago,
      ends_at_utc: 10.minutes.ago,
      meeting_capture_enabled: false,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/auto-stop-ended" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Ended online session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "recording",
      join_url: "https://meet.google.com/auto-stop-ended",
      created_by: user,
      updated_by: user
    )
    run = MeetingBotRun.create!(
      meeting_session: session,
      provider: "google_meet",
      status: "recording"
    )

    described_class.perform_now

    session.reload
    run.reload
    expect(session.status).to eq("cancelled")
    expect(session.error_message).to include("capture stopped automatically")
    expect(run.status).to eq("failed")
    expect(run.error_message).to include("capture stopped automatically")
  end
end
