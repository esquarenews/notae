require "rails_helper"

RSpec.describe Meetings::SpeakerResolutionService do
  def build_session(suffix:)
    user = User.create!(email: "meeting-speaker-resolution-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Speaker Resolution #{suffix}", slug: "speaker-resolution-#{suffix}")
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
      title: "Speaker sync",
      starts_at_utc: 1.hour.from_now,
      ends_at_utc: 2.hours.from_now,
      metadata_json: {
        "invitees" => [
          { "name" => "Alex", "email" => "alex@example.com" },
          { "name" => "Sam", "email" => "sam@example.com" }
        ]
      }
    )
    MeetingSession.create!(
      workspace: workspace,
      kalendarium_event: event,
      title: "Speaker session",
      capture_mode: "upload",
      provider: "local",
      status: "processing",
      created_by: user,
      updated_by: user
    )
  end

  it "maps speakers to invitees and supports manual alias overrides" do
    session = build_session(suffix: "mapping")
    service = described_class.new(session: session)

    turns = [
      Meetings::LocalDiarizer::Turn.new(position: 0, started_ms: 0, ended_ms: 1000, speaker_key: "S1", text: "Hello", confidence: 0.7),
      Meetings::LocalDiarizer::Turn.new(position: 1, started_ms: 1000, ended_ms: 2000, speaker_key: "S2", text: "Hi", confidence: 0.68)
    ]

    resolved = service.resolve(turns: turns)
    expect(resolved.map(&:speaker_name)).to eq(["Alex", "Sam"])

    resolved.each do |turn|
      session.meeting_utterances.create!(
        position: turn.position,
        started_ms: turn.started_ms,
        ended_ms: turn.ended_ms,
        speaker_key: turn.speaker_key,
        speaker_name: turn.speaker_name,
        text: turn.text
      )
    end

    service.apply_manual_mapping!({ "S2" => "Samantha" })
    expect(session.meeting_utterances.find_by!(speaker_key: "S2").speaker_name).to eq("Samantha")
  end
end
