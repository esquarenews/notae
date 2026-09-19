require "json"

module Meetings
  class SummaryAndActionsService
    MODEL = "gpt-5.6-terra".freeze
    MAX_ACTION_ITEMS = 8
    MIN_ACTION_CONFIDENCE = 0.55
    ACTION_VERB_PATTERN = /\b(send|share|draft|prepare|create|update|schedule|book|assign|deliver|review|finalize|publish|follow up|email|call|confirm|submit|build|implement|fix|investigate|coordinate|sync|document|write|approve|plan)\b/i
    NON_ACTION_PREFIX_PATTERN = /\A(?:discuss|consider|think about|explore|brainstorm|maybe|possibly|tbd)\b/i

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
        reasoning: { effort: "medium" },
        prompt_cache_key: "notae-meeting-summary-v1",
        prompt_cache_options: { ttl: "30m" },
        max_output_tokens: 900
      )

      payload = parse_response_payload(response[:text])
      summary_markdown = summary_markdown_for(payload)
      action_items = normalize_action_items(payload["action_items"])

      Search::AiUsageLogger.log!(
        user: session.created_by,
        workspace: session.workspace,
        operation: AiUsageLog::OP_MEETING_SUMMARY,
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
        - Include at most #{MAX_ACTION_ITEMS} action items.
        - Output only concrete commitments that someone can execute.
        - Do not invent tasks; use only statements grounded in the transcript.
        - Exclude vague statements (for example "discuss", "consider", "think about", "explore").
        - Prefer actions with explicit owner and/or due date.
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
      seen_titles = {}

      Array(raw_items).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        next if title.blank?
        next if non_actionable_title?(title)
        next unless actionable_title?(title)

        normalized_title = title.downcase.gsub(/\s+/, " ").strip
        next if seen_titles[normalized_title]

        owner = item["owner"].to_s.strip
        due_at = parse_due_at(item["due_at"])
        confidence = item["confidence"].to_f
        confidence = confidence.clamp(0.0, 1.0)
        next if confidence < MIN_ACTION_CONFIDENCE

        seen_titles[normalized_title] = true

        {
          "title" => title,
          "owner" => owner,
          "due_at" => due_at,
          "confidence" => confidence
        }
      end.first(MAX_ACTION_ITEMS)
    end

    def actionable_title?(title)
      title.match?(ACTION_VERB_PATTERN)
    end

    def non_actionable_title?(title)
      title.match?(NON_ACTION_PREFIX_PATTERN)
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
