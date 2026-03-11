require "rails_helper"

RSpec.describe Meetings::TranscriptIngestService do
  include ActiveJob::TestHelper

  def build_session(suffix:)
    user = User.create!(email: "meeting-transcript-ingest-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Transcript Ingest #{suffix}", slug: "transcript-ingest-#{suffix}")
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
      title: "Transcript ingest event",
      starts_at_utc: 1.hour.ago,
      ends_at_utc: 15.minutes.ago,
      metadata_json: {
        "invitees" => [
          { "name" => "Errol" }
        ]
      }
    )
    MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Transcript ingest session",
      capture_mode: "online_bot",
      provider: "google_meet",
      status: "recording",
      created_by: user,
      updated_by: user
    )
  end

  before do
    clear_enqueued_jobs
  end

  it "persists utterances, updates transcript text, and queues summarization" do
    session = build_session(suffix: "ingest")

    described_class.new(session: session, actor: session.updated_by).ingest!(
      utterances: [
        {
          speaker_key: "S1",
          speaker_name: "Errol",
          text: "Welcome everyone",
          started_ms: 0,
          ended_ms: 1200,
          confidence: 0.91
        },
        {
          speaker_key: "S2",
          speaker_name: "Alex",
          text: "Thanks for joining",
          started_ms: 1300,
          ended_ms: 2500,
          confidence: 0.88
        }
      ],
      metadata: { "transcript_source" => "meeting_bot_captions" }
    )

    session.reload
    expect(session.status).to eq("summarizing")
    expect(session.error_message).to be_blank
    expect(session.metadata_json["transcript_source"]).to eq("meeting_bot_captions")
    expect(session.transcript_text).to include("[00:00] Errol: Welcome everyone")
    expect(session.transcript_text).to include("[00:01] Alex: Thanks for joining")
    expect(session.meeting_utterances.ordered.pluck(:speaker_name, :text)).to eq([
      [ "Errol", "Welcome everyone" ],
      [ "Alex", "Thanks for joining" ]
    ])
    expect(enqueued_jobs.map { |job| job[:job] }).to include(Meetings::SummarizeSessionJob)
  end
end
