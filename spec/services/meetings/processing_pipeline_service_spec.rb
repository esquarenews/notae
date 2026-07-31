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

  it "raises an attempts-exhausted error after repeated connection failures" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush

    allow(service).to receive(:sleep)
    allow(Openai::AudioTranscriptionsClient).to receive(:transcribe)
      .with(hash_including(file_path: file.path, model: "gpt-4o-transcribe-diarize", response_format: "diarized_json", chunking_strategy: "auto"))
      .and_raise(Openai::AudioTranscriptionsClient::ConnectionError, "Transcription API connection failed: timed out")

    expect do
      service.send(:transcribe_with_preferred_formats, file.path)
    end.to raise_error(Openai::AudioTranscriptionsClient::ConnectionError, /after 3 attempts/)

    expect(service).to have_received(:sleep).with(1.second).once
    expect(service).to have_received(:sleep).with(2.seconds).once
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

  it "transcribes long captures in chunks and offsets merged segment timestamps" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush
    chunk_dir = Dir.mktmpdir("meeting-chunks-spec")
    chunker = instance_double(Meetings::AudioChunker)
    first_chunk = Meetings::AudioChunker::Chunk.new(path: "/tmp/chunk-001.mp3", start_offset_seconds: 0.0, duration_seconds: 1200.0)
    second_chunk = Meetings::AudioChunker::Chunk.new(path: "/tmp/chunk-002.mp3", start_offset_seconds: 1200.0, duration_seconds: 337.5)

    allow(service).to receive(:audio_duration_seconds).with(file.path).and_return(1537.57625)
    allow(Meetings::AudioChunker).to receive(:available?).and_return(true)
    allow(Meetings::AudioChunker).to receive(:new)
      .with(max_chunk_duration_seconds: described_class::TRANSCRIPTION_CHUNK_DURATION_SECONDS)
      .and_return(chunker)
    allow(chunker).to receive(:split!).with(file_path: file.path).and_return(
      { directory: chunk_dir, chunks: [ first_chunk, second_chunk ] }
    )
    allow(service).to receive(:transcribe_with_preferred_formats).with(first_chunk.path).and_return(
      {
        "text" => "First chunk",
        "segments" => [ { "start" => 0.0, "end" => 3.5, "text" => "Hello", "speaker" => "speaker_a" } ],
        "usage" => { "input_tokens" => 50, "output_tokens" => 15, "total_tokens" => 65 }
      }
    )
    allow(service).to receive(:transcribe_with_preferred_formats).with(second_chunk.path).and_return(
      {
        "text" => "Second chunk",
        "segments" => [ { "start" => 1.25, "end" => 4.75, "text" => "Back again", "speaker" => "speaker_b" } ],
        "usage" => { "input_tokens" => 40, "output_tokens" => 12, "total_tokens" => 52 }
      }
    )

    response = service.send(:transcribe_audio_file, file.path)

    expect(response["text"]).to eq("First chunk\n\nSecond chunk")
    expect(response["segments"]).to eq([
      { "start" => 0.0, "end" => 3.5, "text" => "Hello", "speaker" => "speaker_a" },
      { "start" => 1201.25, "end" => 1204.75, "text" => "Back again", "speaker" => "speaker_b" }
    ])
    expect(response["usage"]).to eq({ "input_tokens" => 90, "output_tokens" => 27, "total_tokens" => 117 })
    expect(response["chunk_count"]).to eq(2)
    expect(Dir.exist?(chunk_dir)).to be(false)
  ensure
    file.close
    file.unlink
  end

  it "falls back to chunking when the transcription API rejects the full capture for duration" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush
    chunk_dir = Dir.mktmpdir("meeting-chunks-duration-spec")
    chunker = instance_double(Meetings::AudioChunker)
    chunk = Meetings::AudioChunker::Chunk.new(path: "/tmp/chunk-001.mp3", start_offset_seconds: 0.0, duration_seconds: 900.0)

    allow(service).to receive(:audio_duration_seconds).with(file.path).and_raise(Meetings::AudioChunker::Error, "probe unavailable")
    allow(Meetings::AudioChunker).to receive(:available?).and_return(true)
    allow(Meetings::AudioChunker).to receive(:new)
      .with(max_chunk_duration_seconds: described_class::TRANSCRIPTION_CHUNK_DURATION_SECONDS)
      .and_return(chunker)
    allow(chunker).to receive(:split!).with(file_path: file.path).and_return(
      { directory: chunk_dir, chunks: [ chunk ] }
    )
    allow(service).to receive(:transcribe_with_preferred_formats) do |path|
      if path == file.path
        raise Openai::AudioTranscriptionsClient::Error, "audio duration 1537.57625 seconds is longer than 1400 seconds which is the maximum for this model"
      end

      { "text" => "Recovered from chunks", "usage" => { "input_tokens" => 12, "output_tokens" => 4, "total_tokens" => 16 } }
    end

    response = service.send(:transcribe_audio_file, file.path)

    expect(response["text"]).to eq("Recovered from chunks")
    expect(response["usage"]).to eq({ "input_tokens" => 12, "output_tokens" => 4, "total_tokens" => 16 })
    expect(Dir.exist?(chunk_dir)).to be(false)
  ensure
    file.close
    file.unlink
  end

  it "raises a clear error when long captures need chunking but ffmpeg is unavailable" do
    service = build_service
    file = Tempfile.new([ "meeting-capture", ".webm" ])
    file.write("audio")
    file.flush

    allow(service).to receive(:audio_duration_seconds).with(file.path).and_return(1537.57625)
    allow(Meetings::AudioChunker).to receive(:available?).and_return(false)

    expect do
      service.send(:transcribe_audio_file, file.path)
    end.to raise_error(Openai::AudioTranscriptionsClient::Error, /ffmpeg\/ffprobe/)
  ensure
    file.close
    file.unlink
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

  it "uses audio duration to estimate transcription cost when token usage is absent" do
    service = build_service
    service.instance_variable_set(:@last_transcription_model, "gpt-4o-transcribe-diarize")
    service.instance_variable_set(:@transcription_duration_seconds, 600.0)
    allow(Search::AiUsageLogger).to receive(:log!)

    service.send(:log_transcription_usage!, {})

    expect(Search::AiUsageLogger).to have_received(:log!).with(
      hash_including(
        model: "gpt-4o-transcribe-diarize",
        usage: hash_including(audio_minutes: 10.0),
        metadata: hash_including(audio_minutes: 10.0)
      )
    )
  end
end
