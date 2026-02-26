module Search
  class WorkspaceAnswerService
    Answer = Struct.new(:summary, :sources, keyword_init: true)

    MODEL = "gpt-4o-mini"
    CONTEXT_RESULT_LIMIT = 8

    attr_reader :unavailable_reason

    def initialize(user:, workspace:, query:, results:)
      @user = user
      @workspace = workspace
      @query = query.to_s.strip
      @results = Array(results)
      @unavailable_reason = nil
    end

    def call
      return unavailable(:blank_query) if query.blank?
      return unavailable(:missing_api_key) unless user.openai_api_key_configured?
      return unavailable(:budget_exceeded) unless Search::AiBudgetGuard.within_daily_budget?(user: user, workspace: workspace)
      return unavailable(:rate_limited) unless Search::AiRateLimiter.allowed?(user: user, workspace: workspace, operation: "answer_generation")

      context_results = results.first(CONTEXT_RESULT_LIMIT)
      return unavailable(:no_context) if context_results.empty?

      response = Openai::ResponsesClient.generate_text_with_usage(
        prompt: prompt_for(context_results),
        api_key: user.openai_api_key,
        model: MODEL
      )
      response_text = response[:text].to_s.strip
      return unavailable(:empty_response) if response_text.blank?

      Search::AiUsageLogger.log!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_SEARCH_ANSWER,
        model: MODEL,
        usage: response[:usage],
        metadata: { context_results: context_results.length, query_length: query.length }
      )

      Answer.new(
        summary: response_text,
        sources: context_results.map.with_index do |result, index|
          {
            index: index + 1,
            title: result.title,
            kind: result.kind,
            url: result.url
          }
        end
      )
    rescue Openai::ResponsesClient::Error => e
      Rails.logger.warn("AI workspace answer disabled for workspace=#{workspace.id}: #{e.message}")
      unavailable(:provider_error)
    end

    private

    attr_reader :user, :workspace, :query, :results

    def prompt_for(context_results)
      lines = context_results.map.with_index do |result, index|
        excerpt = ActionView::Base.full_sanitizer.sanitize(result.excerpt.to_s).squish
        "[#{index + 1}] Kind=#{result.kind}; Title=#{result.title}; Excerpt=#{excerpt}"
      end

      <<~PROMPT
        You answer questions using only the provided workspace search context.
        If the context is insufficient, say you are unsure and ask for a narrower question.
        Keep the answer concise and factual.
        Include source references as [n] markers matching the context entries.

        Workspace: #{workspace.name}
        Query: #{query}

        Context:
        #{lines.join("\n")}
      PROMPT
    end

    def unavailable(reason)
      @unavailable_reason = reason
      nil
    end
  end
end
