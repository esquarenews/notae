require "json"

module Search
  class KnowledgeSuggestionService
    Response = Struct.new(:summary, :insights, :task_suggestions, :related_notes, :sources, :model, keyword_init: true)

    MODEL = "gpt-4.1-mini".freeze
    CONTEXT_LIMIT = 12

    attr_reader :unavailable_reason

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
      @unavailable_reason = nil
    end

    def call
      return unavailable(:missing_api_key) unless user.openai_api_key_configured?
      return unavailable(:budget_exceeded) unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)
      return unavailable(:rate_limited) unless Search::AiRateLimiter.allowed?(user: user, workspace: workspace, operation: "answer_generation")

      context_chunks = select_context_chunks
      return unavailable(:no_context) if context_chunks.empty?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: prompt_for(context_chunks),
        api_key: user.openai_api_key,
        model: MODEL,
        max_output_tokens: 900
      )
      payload = parse_payload(response[:text])
      normalized = normalize_payload(payload, context_chunks.length)

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION,
        model: MODEL,
        usage: response[:usage],
        metadata: {
          context_chunks: context_chunks.length,
          feature: "knowledge_suggestion_service"
        }
      )

      Response.new(
        summary: normalized[:summary],
        insights: normalized[:insights],
        task_suggestions: normalized[:task_suggestions],
        related_notes: normalized[:related_notes],
        sources: normalized[:used_indices].map { |index| source_payload_for(context_chunks[index - 1], index) },
        model: MODEL
      )
    rescue Openai::ResponsesClient::Error => error
      Rails.logger.warn("Knowledge suggestion generation failed for workspace=#{workspace.id}: #{error.message}")
      unavailable(:provider_error)
    end

    private

    attr_reader :user, :workspace

    def select_context_chunks
      accessible_chunks_scope.order(updated_at: :desc).limit(80).to_a
                             .group_by { |chunk| [ chunk.source_type, chunk.source_id ] }
                             .values
                             .map(&:first)
                             .first(CONTEXT_LIMIT)
    end

    def accessible_chunks_scope
      page_ids = Pundit.policy_scope!(user, Page).for_workspace(workspace).active.select(:id)
      row_ids = Pundit.policy_scope!(user, DbRow).for_workspace(workspace).active.select(:id)
      event_ids = Pundit.policy_scope!(user, KalendariumEvent).for_workspace(workspace).select(:id)
      meeting_ids = Pundit.policy_scope!(user, MeetingSession).for_workspace(workspace).select(:id)
      base = SearchChunk.for_workspace(workspace)

      SearchChunk.accessible_scope_from(
        base: base,
        page_ids: page_ids,
        row_ids: row_ids,
        event_ids: event_ids,
        meeting_ids: meeting_ids
      )
    end

    def prompt_for(context_chunks)
      context_lines = context_chunks.map.with_index do |chunk, index|
        entities = Array(chunk.metadata_json.to_h["entities"]&.values).flatten.uniq.first(8).join(", ")
        "[#{index + 1}] Kind=#{chunk.source_type}; Title=#{chunk.source_title}; URI=#{chunk.source_uri}; Entities=#{entities}; Excerpt=#{chunk.text}"
      end

      <<~PROMPT
        You are building a read-only knowledge brief for a workspace.
        Use only the provided context.
        Return JSON only with this shape:
        {
          "summary": "short paragraph with citations like [1]",
          "insights": ["insight with citations"],
          "task_suggestions": [
            {
              "title": "short suggestion",
              "owner": "person name or empty string",
              "rationale": "why this matters with citations",
              "citation_indices": [1, 2]
            }
          ],
          "related_notes": [
            {
              "title": "note or source title",
              "reason": "why it is related with citations",
              "citation_indices": [1]
            }
          ]
        }
        Rules:
        - Every summary, insight, suggestion rationale, and related note reason must be grounded in citations.
        - Do not invent owners or tasks.
        - Keep the response concise and actionable.
        - Prefer concrete next-step suggestions over generic advice.

        Workspace: #{workspace.name}

        Context:
        #{context_lines.join("\n")}
      PROMPT
    end

    def parse_payload(raw)
      value = raw.to_s.strip
      return {} if value.blank?

      JSON.parse(value[/\{.*\}/m] || value)
    rescue JSON::ParserError
      {}
    end

    def normalize_payload(payload, max_index)
      used_indices = []
      summary = normalize_cited_text(payload["summary"], max_index, used_indices)
      insights = Array(payload["insights"]).filter_map { |item| normalize_cited_text(item, max_index, used_indices) }.first(6)
      task_suggestions = Array(payload["task_suggestions"]).filter_map do |item|
        normalize_task_suggestion(item, max_index, used_indices)
      end.first(8)
      related_notes = Array(payload["related_notes"]).filter_map do |item|
        normalize_related_note(item, max_index, used_indices)
      end.first(8)

      used_indices = [1] if used_indices.empty?
      summary = "#{summary.presence || 'Knowledge summary unavailable.'} [1]" if summary.to_s.exclude?("[")

      {
        summary: summary,
        insights: insights,
        task_suggestions: task_suggestions,
        related_notes: related_notes,
        used_indices: used_indices.uniq.sort
      }
    end

    def normalize_task_suggestion(item, max_index, used_indices)
      return unless item.is_a?(Hash)

      title = item["title"].to_s.strip
      return if title.blank?

      rationale = normalize_cited_text(item["rationale"], max_index, used_indices)
      citation_indices = normalize_citation_indices(item["citation_indices"], max_index, used_indices)
      {
        "title" => title,
        "owner" => item["owner"].to_s.strip,
        "rationale" => rationale,
        "citation_indices" => citation_indices
      }
    end

    def normalize_related_note(item, max_index, used_indices)
      return unless item.is_a?(Hash)

      title = item["title"].to_s.strip
      return if title.blank?

      reason = normalize_cited_text(item["reason"], max_index, used_indices)
      citation_indices = normalize_citation_indices(item["citation_indices"], max_index, used_indices)
      {
        "title" => title,
        "reason" => reason,
        "citation_indices" => citation_indices
      }
    end

    def normalize_cited_text(value, max_index, used_indices)
      text = value.to_s.strip
      return if text.blank?

      cleaned = text.gsub(/\[(\d+)\]/) do |_match|
        index = Regexp.last_match(1).to_i
        if index.between?(1, max_index)
          used_indices << index
          "[#{index}]"
        else
          ""
        end
      end.gsub(/[ \t]+\n/, "\n").gsub(/[ \t]{2,}/, " ").strip
      return if cleaned.blank?

      if cleaned.scan(/\[(\d+)\]/).flatten.empty?
        used_indices << 1
        cleaned = "#{cleaned} [1]"
      end

      cleaned
    end

    def normalize_citation_indices(value, max_index, used_indices)
      indices = Array(value).map(&:to_i).select { |index| index.between?(1, max_index) }.uniq
      if indices.empty?
        indices = used_indices.last.present? ? [ used_indices.last ] : [ 1 ]
      end
      used_indices.concat(indices)
      indices
    end

    def source_payload_for(chunk, index)
      chunk.provenance_payload.merge(
        index: index,
        kind: source_kind_label(chunk),
        title: chunk.source_title,
        url: chunk.source_uri,
        workspace_name: chunk.workspace.name
      )
    end

    def source_kind_label(chunk)
      case chunk.source_type
      when SearchChunk::SOURCE_PAGE then "Page"
      when SearchChunk::SOURCE_DB_ROW then "Row"
      when SearchChunk::SOURCE_KALENDARIUM_EVENT then "Kalendarium event"
      when SearchChunk::SOURCE_MEETING_SESSION then "Meeting session"
      else chunk.source_type.to_s.humanize
      end
    end

    def unavailable(reason)
      @unavailable_reason = reason
      nil
    end
  end
end
