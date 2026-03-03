require "json"

module Meetings
  class SummaryAndActionsService
    MODEL = "gpt-4.1-mini".freeze

    def initialize(session:)
      @session = session
    end

    def call
      transcript = session.transcript_text.to_s.strip
      return { summary_markdown: "No transcript available.", action_items: [] } if transcript.blank?
      return fallback_summary(transcript) unless session.created_by.openai_api_key_configured?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: summary_prompt(transcript),
        api_key: session.created_by.openai_api_key,
        model: MODEL,
        max_output_tokens: 900
      )

      payload = parse_response_payload(response[:text])
      summary_markdown = summary_markdown_for(payload)
      action_items = normalize_action_items(payload["action_items"])

      Search::AiUsageLogger.log!(
        user: session.created_by,
        workspace: session.workspace,
        operation: AiUsageLog::OP_ASSISTANT_WRITE,
        model: MODEL,
        usage: response[:usage],
        metadata: {
          feature: "meetings_summary",
          meeting_session_id: session.id
        }
      )

      {
        summary_markdown: summary_markdown,
        action_items: action_items
      }
    rescue Openai::ResponsesClient::Error
      fallback_summary(transcript)
    end

    private

    attr_reader :session

    def summary_prompt(transcript)
      <<~PROMPT
        You are creating structured meeting notes for a collaboration app.
        Return JSON only with this schema:
        {
          "summary_bullets": ["..."],
          "decisions": ["..."],
          "action_items": [
            {
              "title": "short action",
              "owner": "person name or empty string",
              "due_at": "ISO8601 timestamp or empty string",
              "confidence": 0.0
            }
          ]
        }
        Rules:
        - Keep summary concise and factual.
        - Include at most 8 action items.
        - Use empty strings for unknown owner/due_at.
        - Confidence must be between 0 and 1.

        Transcript:
        #{transcript}
      PROMPT
    end

    def parse_response_payload(raw)
      return {} if raw.to_s.strip.blank?

      trimmed = raw.to_s.strip
      json_candidate = trimmed[/\{.*\}/m] || trimmed
      parsed = JSON.parse(json_candidate)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def summary_markdown_for(payload)
      summary_lines = Array(payload["summary_bullets"]).map { |line| line.to_s.strip }.reject(&:blank?).first(8)
      decision_lines = Array(payload["decisions"]).map { |line| line.to_s.strip }.reject(&:blank?).first(6)

      sections = []
      sections << [ "Summary", summary_lines ]
      sections << [ "Decisions", decision_lines ]

      sections.filter_map do |heading, lines|
        next if lines.empty?

        <<~SECTION.strip
          ### #{heading}
          #{lines.map { |line| "- #{line}" }.join("\n")}
        SECTION
      end.join("\n\n").presence || "Summary unavailable."
    end

    def normalize_action_items(raw_items)
      Array(raw_items).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        next if title.blank?

        owner = item["owner"].to_s.strip
        due_at = parse_due_at(item["due_at"])
        confidence = item["confidence"].to_f
        confidence = confidence.clamp(0.0, 1.0)

        {
          "title" => title,
          "owner" => owner,
          "due_at" => due_at,
          "confidence" => confidence
        }
      end.first(12)
    end

    def parse_due_at(raw_value)
      value = raw_value.to_s.strip
      return nil if value.blank?

      parsed = Time.zone.parse(value)
      parsed&.utc&.iso8601
    rescue ArgumentError, TypeError
      nil
    end

    def fallback_summary(transcript)
      sentences = transcript.split(/(?<=[.!?])\s+/).map(&:strip).reject(&:blank?).first(4)
      summary_lines = sentences.map { |sentence| "- #{sentence}" }.join("\n")

      {
        summary_markdown: summary_lines.presence || "Summary unavailable.",
        action_items: []
      }
    end
  end
end
