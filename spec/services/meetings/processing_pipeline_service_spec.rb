require "rails_helper"
require "ostruct"

RSpec.describe Meetings::ProcessingPipelineService do
  def build_service
    user = OpenStruct.new(openai_api_key: "sk-test")
    workspace = OpenStruct.new(id: "workspace-1")
    session = OpenStruct.new(id: "session-1", created_by: user, workspace: workspace)
    described_class.new(session: session)
  end

  it "falls back to fresh transcription text when segment timestamps are unavailable" do
    service = build_service

    normalized = service.send(:normalize_segments, {}, "Fresh transcript text")
    segments = normalized.fetch(:segments)

    expect(segments).to eq([ { start: 0.0, end: 1.0, text: "Fresh transcript text" } ])
    expect(normalized.fetch(:source)).to eq(:fallback)
  end

  it "derives sentence segments from transcript text when multiple sentences are present" do
    service = build_service

    normalized = service.send(:normalize_segments, {}, "First speaker sentence. Second speaker sentence?")
    segments = normalized.fetch(:segments)

    expect(segments.length).to eq(2)
    expect(segments[0][:text]).to eq("First speaker sentence.")
    expect(segments[1][:text]).to eq("Second speaker sentence?")
    expect(segments[1][:start]).to be > segments[0][:end]
    expect(normalized.fetch(:source)).to eq(:synthetic)
  end

  it "chunks long single-sentence transcript text into multiple fallback segments" do
    service = build_service
    text = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega"

    normalized = service.send(:normalize_segments, {}, text)
    segments = normalized.fetch(:segments)

    expect(segments.length).to be >= 2
    expect(segments.map { |segment| segment[:text] }.join(" ")).to include("alpha beta")
    expect(segments[0][:start]).to eq(0.0)
    expect(segments[1][:start]).to be > segments[0][:end]
    expect(normalized.fetch(:source)).to eq(:synthetic)
  end

  it "retries transcription with json when diarized_json is rejected by model" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush

    allow(Openai::AudioTranscriptionsClient).to receive(:transcribe)
      .with(hash_including(file_path: file.path, model: "gpt-4o-transcribe-diarize", response_format: "diarized_json", chunking_strategy: "auto"))
      .and_raise(Openai::AudioTranscriptionsClient::Error, "response_format 'diarized_json' is not compatible")
    allow(Openai::AudioTranscriptionsClient).to receive(:transcribe)
      .with(hash_including(file_path: file.path, model: "gpt-4o-transcribe-diarize", response_format: "json", chunking_strategy: "auto"))
      .and_return({ "text" => "ok" })

    response = service.send(:transcribe_with_preferred_formats, file.path)
    expect(response).to eq({ "text" => "ok" })
  ensure
    file.close
    file.unlink
  end

  it "retries transient transcription connection failures before succeeding" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush

    allow(service).to receive(:sleep)
    attempts = 0
    allow(Openai::AudioTranscriptionsClient).to receive(:transcribe)
      .with(hash_including(file_path: file.path, model: "gpt-4o-transcribe-diarize", response_format: "diarized_json", chunking_strategy: "auto")) do
        attempts += 1
        raise Openai::AudioTranscriptionsClient::ConnectionError, "Transcription API connection failed: timed out" if attempts == 1

        { "text" => "ok after retry" }
      end

    response = service.send(:transcribe_with_preferred_formats, file.path)

    expect(response).to eq({ "text" => "ok after retry" })
    expect(service).to have_received(:sleep).with(1.second).once
  ensure
    file.close
    file.unlink
  end

  it "maps diarized speaker labels into stable meeting speaker keys" do
    service = build_service
    turns = service.send(:turns_from_speaker_segments, [
      { start: 0.0, end: 1.1, text: "Hello", speaker: "speaker_a" },
      { start: 1.2, end: 2.4, text: "Hi", speaker: "speaker_b" },
      { start: 2.5, end: 3.1, text: "Follow up", speaker: "speaker_a" }
    ])

    expect(turns.map(&:speaker_key)).to eq([ "S1", "S2", "S1" ])
    expect(turns.map(&:text)).to eq([ "Hello", "Hi", "Follow up" ])
  end

  it "logs transcription usage for meeting AI usage tracking" do
    service = build_service
    allow(Search::AiUsageLogger).to receive(:log!)
    service.instance_variable_set(:@last_transcription_model, "gpt-4o-transcribe-diarize")

    service.send(:log_transcription_usage!, {
      "usage" => {
        "input_tokens" => 320,
        "output_tokens" => 90,
        "total_tokens" => 410
      }
    })

    expect(Search::AiUsageLogger).to have_received(:log!).with(
      hash_including(
        operation: AiUsageLog::OP_MEETING_TRANSCRIPTION,
        model: "gpt-4o-transcribe-diarize",
        usage: { prompt_tokens: 320, completion_tokens: 90, total_tokens: 410 }
      )
    )
  end

  it "ignores transcription usage logging when no usage is returned" do
    service = build_service
    allow(Search::AiUsageLogger).to receive(:log!)

    service.send(:log_transcription_usage!, {})

    expect(Search::AiUsageLogger).not_to have_received(:log!)
  end
end
