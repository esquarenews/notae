module Search
  class WorkspaceAnswerService
    Answer = Struct.new(:summary, :sources, keyword_init: true)

    MODEL = "gpt-4o-mini"
    CONTEXT_RESULT_LIMIT = 8

    def initialize(user:, workspace:, query:, results:)
      @user = user
      @workspace = workspace
      @query = query.to_s.strip
      @results = Array(results)
    end

    def call
      return nil if query.blank?
      return nil unless user.openai_api_key_configured?

      context_results = results.first(CONTEXT_RESULT_LIMIT)
      return nil if context_results.empty?

      response_text = Openai::ResponsesClient.generate_text(
        prompt: prompt_for(context_results),
        api_key: user.openai_api_key,
        model: MODEL
      ).strip
      return nil if response_text.blank?

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
      nil
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
  end
end
