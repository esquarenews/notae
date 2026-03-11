module Api
  module V1
    module Knowledge
      class SuggestionsController < BaseController
        before_action :set_workspace!

        def index
          service = Search::KnowledgeSuggestionService.new(user: current_user, workspace: workspace)
          suggestion = service.call
          return render_unavailable(service.unavailable_reason) if suggestion.blank?

          render json: {
            data: {
              summary: suggestion.summary,
              insights: suggestion.insights,
              task_suggestions: suggestion.task_suggestions,
              related_notes: suggestion.related_notes,
              sources: suggestion.sources,
              model: suggestion.model
            }
          }, status: :ok
        end

        private

        def render_unavailable(reason)
          case reason
          when :missing_api_key
            render_error(code: "missing_api_key", message: "Configure an OpenAI key first", status: :unprocessable_entity)
          when :budget_exceeded
            render_error(code: "budget_exceeded", message: "AI budget reached", status: :too_many_requests)
          when :rate_limited
            render_error(code: "rate_limited", message: "AI rate limit exceeded", status: :too_many_requests)
          when :no_context
            render_error(code: "no_context", message: "No indexed knowledge is available yet", status: :unprocessable_entity)
          else
            render_error(code: "provider_error", message: "Knowledge suggestion request failed", status: :bad_gateway)
          end
        end
      end
    end
  end
end
