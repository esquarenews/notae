require "tempfile"

module Meetings
  class ProcessingPipelineService
    class Error < StandardError; end

    def initialize(session:)
      @session = session
    end

    def call
      raise Error, "Meeting session capture file is missing" unless capture_attachment.present?
      raise Error, "OpenAI API key is not configured for this user" unless session.created_by.openai_api_key_configured?

      session.update!(status: "processing", error_message: nil)
      transcription = transcribe_capture_file!
      turns = Meetings::LocalDiarizer.call(segments: transcription.fetch(:segments))
      resolved_turns = Meetings::SpeakerResolutionService.new(session: session).resolve(turns: turns)

      MeetingSession.transaction do
        session.meeting_utterances.delete_all
        resolved_turns.each do |turn|
          session.meeting_utterances.create!(
            position: turn.position,
            started_ms: turn.started_ms,
            ended_ms: turn.ended_ms,
            speaker_key: turn.speaker_key,
            speaker_name: turn.speaker_name,
            text: turn.text,
            confidence: turn.confidence
          )
        end

        session.update!(
          transcript_text: transcript_for(resolved_turns),
          status: "summarizing",
          error_message: nil
        )
      end

      session
    rescue Openai::AudioTranscriptionsClient::Error => error
      raise Error, error.message
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :session

    def capture_attachment
      @capture_attachment ||= session.capture_files.attachments.first
    end

    def transcribe_capture_file!
      downloaded_path = Tempfile.create([ "meeting-capture-#{session.id}", capture_extension ], binmode: true)
      downloaded_path.write(capture_attachment.blob.download)
      downloaded_path.flush

      response = Openai::AudioTranscriptionsClient.transcribe(
        file_path: downloaded_path.path,
        api_key: session.created_by.openai_api_key
      )

      {
        text: response["text"].to_s,
        segments: normalize_segments(response["segments"])
      }
    ensure
      downloaded_path&.close!
    end

    def normalize_segments(raw_segments)
      segments = Array(raw_segments).filter_map do |segment|
        text = segment["text"].to_s.strip
        next if text.blank?

        {
          start: segment["start"].to_f,
          end: segment["end"].to_f,
          text: text
        }
      end

      return segments if segments.any?

      transcript = session.transcript_text.to_s.strip
      fallback_text = transcript.presence || "Transcript unavailable."
      [ { start: 0.0, end: 1.0, text: fallback_text } ]
    end

    def transcript_for(turns)
      Array(turns).map do |turn|
        timestamp = milliseconds_to_clock(turn.started_ms.to_i)
        speaker = turn.speaker_name.to_s.presence || turn.speaker_key
        "[#{timestamp}] #{speaker}: #{turn.text}"
      end.join("\n")
    end

    def milliseconds_to_clock(value)
      seconds = [ value / 1000, 0 ].max
      minutes = seconds / 60
      remaining_seconds = seconds % 60
      format("%02d:%02d", minutes, remaining_seconds)
    end

    def capture_extension
      filename = capture_attachment&.filename.to_s
      ext = File.extname(filename)
      ext.present? ? ext : ".webm"
    end
  end
end
