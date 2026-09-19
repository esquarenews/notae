module KnowledgeSuggestions
  class DestinationResolver
    include Rails.application.routes.url_helpers

    def initialize(suggestion:)
      @suggestion = suggestion
    end

    def call
      return if suggestion.blank?

      knowledge_suggestion_path(
        workspace_slug: suggestion.workspace.slug,
        id: suggestion.id,
        anchor: "knowledge-suggestion-#{suggestion.id}"
      )
    end

    private

    attr_reader :suggestion
  end
end
