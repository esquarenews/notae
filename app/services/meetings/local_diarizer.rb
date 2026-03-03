require "digest"

module Meetings
  class LocalDiarizer
    Turn = Struct.new(:position, :started_ms, :ended_ms, :speaker_key, :text, :confidence, keyword_init: true)

    DEFAULT_CONFIDENCE = 0.62
    GAP_SPLIT_MS = 2_200
    PUNCTUATION_SPLIT = /[.!?]\z/

    def self.call(segments:)
      new(segments: segments).call
    end

    def initialize(segments:)
      @segments = Array(segments)
    end

    def call
      normalized = normalized_segments
      return [] if normalized.empty?

      turns = []
      speaker_index = 0
      previous_end_ms = nil
      current_text = +""
      current_start_ms = nil
      current_end_ms = nil

      normalized.each_with_index do |segment, index|
        start_ms = segment[:start_ms]
        end_ms = segment[:end_ms]
        text = segment[:text]
        gap_ms = previous_end_ms.nil? ? 0 : [ start_ms - previous_end_ms, 0 ].max
        should_split = gap_ms > GAP_SPLIT_MS || current_text.match?(PUNCTUATION_SPLIT)

        if should_split && current_text.present?
          turns << build_turn(
            position: turns.length,
            speaker_key: "S#{(speaker_index % 6) + 1}",
            started_ms: current_start_ms,
            ended_ms: current_end_ms,
            text: current_text
          )
          speaker_index += 1
          current_text = +""
          current_start_ms = nil
        end

        current_start_ms ||= start_ms
        current_end_ms = end_ms
        current_text << " " if current_text.present?
        current_text << text
        previous_end_ms = end_ms

        next unless index == normalized.length - 1

        turns << build_turn(
          position: turns.length,
          speaker_key: "S#{(speaker_index % 6) + 1}",
          started_ms: current_start_ms,
          ended_ms: current_end_ms,
          text: current_text
        )
      end

      turns
    end

    private

    attr_reader :segments

    def normalized_segments
      segments.filter_map do |segment|
        text = segment[:text].to_s.strip
        next if text.blank?

        start_seconds = segment[:start].to_f
        end_seconds = segment[:end].to_f
        end_seconds = start_seconds if end_seconds < start_seconds
        {
          text: text,
          start_ms: (start_seconds * 1000).to_i,
          end_ms: (end_seconds * 1000).to_i
        }
      end
    end

    def build_turn(position:, speaker_key:, started_ms:, ended_ms:, text:)
      Turn.new(
        position: position,
        speaker_key: speaker_key,
        started_ms: started_ms,
        ended_ms: ended_ms,
        text: text.to_s.strip,
        confidence: DEFAULT_CONFIDENCE
      )
    end
  end
end
