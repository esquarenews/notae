module KnowledgeSuggestions
  class DestinationResolver
    include Rails.application.routes.url_helpers

    def initialize(suggestion:)
      @suggestion = suggestion
    end

    def call
      return if suggestion.blank?

      if suggestion.ai_conversation_id.present?
        return workspace_ai_conversation_history_path(
          workspace_slug: suggestion.workspace.slug,
          conversation_id: suggestion.ai_conversation_id,
          anchor: "ai-conversation-#{suggestion.ai_conversation_id}"
        )
      end

      workspace_path(
        suggestion.workspace.slug,
        show_home: 1,
        knowledge_suggestion_id: suggestion.id,
        anchor: "knowledge-suggestion-#{suggestion.id}"
      )
    end

    private

    attr_reader :suggestion
  end
end
