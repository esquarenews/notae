module Meetings
  class TranscriptIngestService
    class Error < StandardError; end
    INTERFACE_TEXT_ERROR = "Transcript only contained Google Meet interface text. Turn captions on and confirm spoken captions are visible before syncing."
    TEXT_STRIP_PATTERNS = [
      /^(?:closed_caption|live captions)\b[:.\s-]*/i,
      /^(?:you\s+)?on live captions are turned on\.?\s*/i,
      /^(?:live\s+)?captions are turned on\.?\s*/i,
      /^(?:live\s+)?captions are turned off\.?\s*/i,
      /^(?:you\s+just\s+then[,:\s-]*)/i,
      /^arrow_downward\s*jump to bottom\.?\s*/i,
      /^jump to bottom\.?\s*/i
    ].freeze

    SYSTEM_TRANSCRIPT_PATTERNS = [
      /your meeting'?s ready/i,
      /closed_caption/i,
      /live captions/i,
      /meeting details/i,
      /or share this joining info with others you want in the meeting/i,
      /join with google meet/i,
      /meet\.google\.com\/[a-z0-9-]+/i,
      /dial-?in:\s*/i,
      /\bpin:\s*\d/i,
      /jump to bottom/i,
      /arrow_downward/i,
      /more phone numbers/i,
      /share full details/i,
      /joined as /i,
      /turn on captions/i,
      /captions are (?:on|off)/i,
      /you (?:left|joined) the meeting/i
    ].freeze

    SYSTEM_SPEAKER_PATTERNS = [
      /\Acaptions?\z/i,
      /\Aclosed_caption\z/i,
      /\Agoogle meet\z/i,
      /\Ameeting details\z/i,
      /\Apresenting\z/i,
      /\Aclose\z/i,
      /\Aperson_add\z/i,
      /\Acontent_copy\z/i,
      /\Adial-?in\z/i,
      /\Acall\z/i,
      /\Ashare\z/i
    ].freeze

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
      normalized_turns = collapse_incremental_turns(normalized_turns)
      normalized_turns = deduplicate_replayed_turns(normalized_turns)
      normalized_turns = reindex_turns(normalized_turns)
      raise Error, "Transcript is empty" if normalized_turns.empty?
      normalized_turns = filter_system_turns(normalized_turns)
      raise Error, INTERFACE_TEXT_ERROR if normalized_turns.empty?
      validate_transcript_quality!(normalized_turns)

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
        text = clean_transcript_text(text)
        next if text.blank?

        started_ms = integer_value(utterance, :started_ms, index * 1_000)
        ended_ms = [ integer_value(utterance, :ended_ms, started_ms + 1_000), started_ms + 250 ].max
        speaker_key = string_value(utterance, :speaker_key).presence || "S#{index + 1}"
        speaker_name = clean_speaker_name(string_value(utterance, :speaker_name).presence)
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
      fallback_text = clean_transcript_text(fallback_text)
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

    def filter_system_turns(turns)
      turns.reject { |turn| system_turn?(turn) }
    end

    def collapse_incremental_turns(turns)
      turns.each_with_object([]) do |turn, collapsed|
        previous = collapsed.last
        if previous && same_speaker?(previous, turn) && incremental_extension?(previous.text, turn.text)
          previous.text = longer_variant(previous.text, turn.text)
          previous.ended_ms = [ previous.ended_ms.to_i, turn.ended_ms.to_i ].max
          previous.confidence = [ previous.confidence.to_f, turn.confidence.to_f ].max
          next
        end

        collapsed << TurnInput.new(**turn.to_h)
      end
    end

    def transcript_for(turns)
      turns.map do |turn|
        timestamp = MeetingSession.milliseconds_to_clock(turn.started_ms.to_i)
        speaker = turn.speaker_name.to_s.presence || turn.speaker_key.to_s
        "[#{timestamp}] #{speaker}: #{turn.text.to_s.strip}"
      end.join("\n")
    end

    def deduplicate_replayed_turns(turns)
      recent_by_signature = {}

      turns.each_with_object([]) do |turn, deduped|
        signature = replay_signature_for(turn)
        prior = signature.present? ? recent_by_signature[signature] : nil

        if prior.present? && replay_duplicate?(prior[:turn], turn)
          prior[:turn].ended_ms = [ prior[:turn].ended_ms.to_i, turn.ended_ms.to_i ].max
          prior[:turn].confidence = [ prior[:turn].confidence.to_f, turn.confidence.to_f ].max
          next
        end

        copy = TurnInput.new(**turn.to_h)
        deduped << copy
        recent_by_signature[signature] = { turn: copy } if signature.present?
      end
    end

    def reindex_turns(turns)
      turns.each_with_index.map do |turn, index|
        TurnInput.new(**turn.to_h.merge(position: index))
      end
    end

    def validate_transcript_quality!(turns)
      return if turns.any? { |turn| !system_turn?(turn) }

      raise Error, INTERFACE_TEXT_ERROR
    end

    def system_turn?(turn)
      speaker_name = turn.speaker_name.to_s.strip
      text = clean_transcript_text(turn.text.to_s)
      combined = [ speaker_name, text ].reject(&:blank?).join(": ")

      SYSTEM_SPEAKER_PATTERNS.any? { |pattern| pattern.match?(speaker_name) } ||
        SYSTEM_TRANSCRIPT_PATTERNS.any? { |pattern| pattern.match?(combined) }
    end

    def clean_transcript_text(value)
      text = value.to_s.strip
      previous = nil

      while text.present? && text != previous
        previous = text
        TEXT_STRIP_PATTERNS.each do |pattern|
          text = text.sub(pattern, "").strip
        end
      end

      text
        .gsub(/\byou\s+just\s+then[,:\s-]*/i, " ")
        .gsub(/arrow_downward\s*jump to bottom/i, "")
        .gsub(/\bclosed_caption\b/i, "")
        .gsub(/\s+/, " ")
        .strip
    end

    def clean_speaker_name(value)
      speaker_name = value.to_s.strip
      return nil if speaker_name.blank?

      speaker_name
    end

    def same_speaker?(left, right)
      left_name = left.speaker_name.to_s.strip
      right_name = right.speaker_name.to_s.strip
      return left_name == right_name if left_name.present? && right_name.present?

      left.speaker_key.to_s == right.speaker_key.to_s
    end

    def incremental_extension?(left, right)
      left_text = canonical_text(left)
      right_text = canonical_text(right)
      return false if left_text.blank? || right_text.blank?

      right_text.start_with?(left_text) || left_text.start_with?(right_text)
    end

    def replay_signature_for(turn)
      speaker = turn.speaker_name.to_s.strip.presence || turn.speaker_key.to_s.strip
      text = canonical_text(turn.text)
      return nil if speaker.blank? || text.blank?

      "#{speaker.downcase}|#{text}"
    end

    def replay_duplicate?(left, right)
      return false unless same_speaker?(left, right)
      return false unless canonical_text(left.text) == canonical_text(right.text)

      elapsed_ms = right.started_ms.to_i - left.started_ms.to_i
      elapsed_ms >= 0 && elapsed_ms <= replay_duplicate_window_ms(right.text)
    end

    def replay_duplicate_window_ms(text)
      normalized = canonical_text(text)
      word_count = normalized.blank? ? 0 : normalized.split.size

      if normalized.length >= 24 || word_count >= 5
        30_000
      elsif normalized.length >= 10 || word_count >= 3
        12_000
      else
        6_000
      end
    end

    def longer_variant(left, right)
      left_text = left.to_s.strip
      right_text = right.to_s.strip
      return left_text if left_text.length >= right_text.length

      right_text
    end

    def canonical_text(value)
      value.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").gsub(/\s+/, " ").strip
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
