module Meetings
  class TranscriptIngestService
    class Error < StandardError; end

    TurnInput = Struct.new(
      :position,
      :started_ms,
      :ended_ms,
      :speaker_key,
      :speaker_name,
      :text,
      :confidence,
      keyword_init: true
    )

    def initialize(session:, actor:)
      @session = session
      @actor = actor
    end

    def ingest!(utterances:, transcript_text: nil, metadata: {})
      normalized_turns = normalize_turns(Array(utterances), transcript_text)
      raise Error, "Transcript is empty" if normalized_turns.empty?

      resolved_turns = Meetings::SpeakerResolutionService.new(session: session).resolve(turns: normalized_turns)

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
          error_message: nil,
          ended_at: session.ended_at || Time.current,
          updated_by: actor,
          metadata_json: session.metadata_json.to_h.merge(metadata.to_h)
        )
      end

      Meetings::SummarizeSessionJob.perform_later(session.id)
      session
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :session, :actor

    def normalize_turns(raw_utterances, transcript_text)
      turns = raw_utterances.filter_map.with_index do |utterance, index|
        next unless utterance.is_a?(Hash)

        text = utterance["text"].to_s.strip.presence || utterance[:text].to_s.strip.presence
        next if text.blank?

        started_ms = integer_value(utterance, :started_ms, index * 1_000)
        ended_ms = [ integer_value(utterance, :ended_ms, started_ms + 1_000), started_ms + 250 ].max
        speaker_key = string_value(utterance, :speaker_key).presence || "S#{index + 1}"
        speaker_name = string_value(utterance, :speaker_name).presence
        confidence = float_value(utterance, :confidence, 0.72)

        TurnInput.new(
          position: index,
          started_ms: started_ms,
          ended_ms: ended_ms,
          speaker_key: speaker_key,
          speaker_name: speaker_name,
          text: text,
          confidence: confidence
        )
      end
      return turns if turns.any?

      fallback_text = transcript_text.to_s.strip
      return [] if fallback_text.blank?

      [ TurnInput.new(
        position: 0,
        started_ms: 0,
        ended_ms: 1_000,
        speaker_key: "S1",
        speaker_name: nil,
        text: fallback_text,
        confidence: 0.5
      ) ]
    end

    def transcript_for(turns)
      turns.map do |turn|
        timestamp = MeetingSession.milliseconds_to_clock(turn.started_ms.to_i)
        speaker = turn.speaker_name.to_s.presence || turn.speaker_key.to_s
        "[#{timestamp}] #{speaker}: #{turn.text.to_s.strip}"
      end.join("\n")
    end

    def string_value(hash, key)
      hash[key.to_s] || hash[key]
    end

    def integer_value(hash, key, default)
      raw = hash[key.to_s] || hash[key]
      return default if raw.nil?

      raw.to_i
    end

    def float_value(hash, key, default)
      raw = hash[key.to_s] || hash[key]
      return default if raw.nil?

      raw.to_f
    end
  end
end
