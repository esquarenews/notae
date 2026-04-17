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

  it "rejects Google Meet interface text masquerading as transcript" do
    session = build_session(suffix: "noise")

    expect {
      described_class.new(session: session, actor: session.updated_by).ingest!(
        utterances: [
          {
            speaker_key: "S1",
            speaker_name: "Your meeting's ready",
            text: "Or share this joining info with others you want in the meeting meet.google.com/abc-defg-hij",
            started_ms: 0,
            ended_ms: 1_200,
            confidence: 0.7
          },
          {
            speaker_key: "S2",
            speaker_name: "call",
            text: "More phone numbers",
            started_ms: 1_300,
            ended_ms: 2_500,
            confidence: 0.7
          }
        ]
      )
    }.to raise_error(
      Meetings::TranscriptIngestService::Error,
      "Transcript only contained Google Meet interface text. Turn captions on and confirm spoken captions are visible before syncing."
    )

    session.reload
    expect(session.meeting_utterances).to be_empty
    expect(session.transcript_text).to be_blank
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Meetings::SummarizeSessionJob)
  end

  it "strips caption chrome and collapses incremental caption growth into the final utterance" do
    session = build_session(suffix: "incremental")

    described_class.new(session: session, actor: session.updated_by).ingest!(
      utterances: [
        {
          speaker_key: "S1",
          speaker_name: "closed_caption",
          text: "Live captions",
          started_ms: 0,
          ended_ms: 300,
          confidence: 0.7
        },
        {
          speaker_key: "S2",
          speaker_name: "You",
          text: "On live captions are turned on.",
          started_ms: 1_000,
          ended_ms: 1_400,
          confidence: 0.8
        },
        {
          speaker_key: "S2",
          speaker_name: "You",
          text: "On live captions are turned on. What was the cause of the success of Heroku?",
          started_ms: 1_500,
          ended_ms: 2_100,
          confidence: 0.82
        },
        {
          speaker_key: "S2",
          speaker_name: "You",
          text: "On live captions are turned on. What was the cause of the success of Heroku? Was it because it was something completely unique?",
          started_ms: 2_200,
          ended_ms: 3_300,
          confidence: 0.84
        }
      ]
    )

    session.reload
    expect(session.meeting_utterances.ordered.pluck(:speaker_name, :text)).to eq([
      [ "You", "What was the cause of the success of Heroku? Was it because it was something completely unique?" ]
    ])
    expect(session.transcript_text).to include("You: What was the cause of the success of Heroku? Was it because it was something completely unique?")
  end
end
