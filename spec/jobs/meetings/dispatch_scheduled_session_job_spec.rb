require "rails_helper"

RSpec.describe Meetings::DispatchScheduledSessionJob, type: :job do
  include ActiveJob::TestHelper

  def build_stack(suffix:)
    user = User.create!(email: "meeting-dispatch-job-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Meeting Dispatch Job #{suffix}", slug: "meeting-dispatch-job-#{suffix}")
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

  it "dispatches a due scheduled session into a queued bot run" do
    user, workspace, calendar = build_stack(suffix: "due")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Due scheduled event",
      starts_at_utc: 1.minute.ago,
      ends_at_utc: 25.minutes.from_now,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/dispatch-due" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Dispatch me",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "scheduled",
      join_url: event.meeting_join_url
    )

    described_class.perform_now(session.id)

    session.reload
    expect(session.status).to eq("joining")
    expect(session.meeting_bot_runs.active.count).to eq(1)
    expect(session.meeting_bot_runs.active.first.status).to eq("queued")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::GuardBotRunJob)
  end

  it "re-enqueues itself when the event start moves further into the future" do
    user, workspace, calendar = build_stack(suffix: "reschedule")
    event = KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      created_by: user,
      updated_by: user,
      title: "Rescheduled event",
      starts_at_utc: 1.hour.from_now,
      ends_at_utc: 2.hours.from_now,
      metadata_json: { "meeting_join_url" => "https://meet.google.com/dispatch-reschedule" }
    )
    session = MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      created_by: user,
      updated_by: user,
      title: "Not due yet",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "scheduled",
      join_url: event.meeting_join_url
    )

    described_class.perform_now(session.id)

    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::DispatchScheduledSessionJob)
    expect(session.reload.status).to eq("scheduled")
    expect(session.meeting_bot_runs.count).to eq(0)
  end
end
