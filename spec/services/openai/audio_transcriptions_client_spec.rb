require "rails_helper"

RSpec.describe Openai::AudioTranscriptionsClient do
  it "uses json response format without timestamp granularities by default" do
    Tempfile.create([ "audio-transcription", ".webm" ]) do |file|
      file.binmode
      file.write("fake audio")
      file.flush

      body = described_class.multipart_body(
        boundary: "----TestBoundary",
        file_path: file.path,
        model: "gpt-4o-mini-transcribe",
        response_format: "json",
        prompt: nil,
        language: nil
      )

      expect(body).to include('name="response_format"')
      expect(body).to include("json")
      expect(body).not_to include('name="timestamp_granularities[]"')
    end
  end

  it "adds timestamp granularities for verbose_json format" do
    Tempfile.create([ "audio-transcription", ".webm" ]) do |file|
      file.binmode
      file.write("fake audio")
      file.flush

      body = described_class.multipart_body(
        boundary: "----TestBoundary",
        file_path: file.path,
        model: "gpt-4o-mini-transcribe",
        response_format: "verbose_json",
        prompt: nil,
        language: nil
      )

      expect(body).to include('name="response_format"')
      expect(body).to include("verbose_json")
      expect(body).to include('name="timestamp_granularities[]"')
    end
  end

  it "serializes diarization options when provided" do
    Tempfile.create([ "audio-transcription", ".webm" ]) do |file|
      file.binmode
      file.write("fake audio")
      file.flush

      body = described_class.multipart_body(
        boundary: "----TestBoundary",
        file_path: file.path,
        model: "gpt-4o-transcribe-diarize",
        response_format: "diarized_json",
        prompt: nil,
        language: nil,
        chunking_strategy: "auto",
        known_speaker_names: [ "Alex", "Sam" ],
        known_speaker_references: [ "data:audio/wav;base64,AAAA", "data:audio/wav;base64,BBBB" ]
      )

      expect(body).to include('name="chunking_strategy"')
      expect(body).to include("auto")
      expect(body).to include('name="known_speaker_names[]"')
      expect(body).to include("Alex")
      expect(body).to include('name="known_speaker_references[]"')
      expect(body).to include("data:audio/wav;base64,AAAA")
    end
  end

  it "raises a connection error for transient network timeouts" do
    Tempfile.create([ "audio-transcription", ".webm" ]) do |file|
      file.binmode
      file.write("fake audio")
      file.flush

      allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout.new("timed out"))

      expect do
        described_class.transcribe(
          file_path: file.path,
          api_key: "sk-test",
          model: "gpt-4o-mini-transcribe",
          response_format: "json"
        )
      end.to raise_error(Openai::AudioTranscriptionsClient::ConnectionError, /Transcription API connection failed/)
    end
  end

  it "uses the extended default read timeout for meeting transcription requests" do
    Tempfile.create([ "audio-transcription", ".webm" ]) do |file|
      file.binmode
      file.write("fake audio")
      file.flush

      response = Net::HTTPOK.new("1.1", "200", "OK")
      allow(response).to receive(:body).and_return('{"text":"ok"}')

      expect(Net::HTTP).to receive(:start).with(
        "api.openai.com",
        443,
        use_ssl: true,
        open_timeout: 8,
        read_timeout: 600
      ).and_yield(instance_double(Net::HTTP, request: response))

      described_class.transcribe(
        file_path: file.path,
        api_key: "sk-test",
        model: "gpt-4o-mini-transcribe",
        response_format: "json"
      )
    end
  end
end
