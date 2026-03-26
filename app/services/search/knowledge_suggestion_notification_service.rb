module Search
  class KnowledgeSuggestionNotificationService
    def initialize(suggestion:, actor: nil)
      @suggestion = suggestion
      @actor = actor || suggestion.user
    end

    def notify_ready!
      Notification.create!(
        workspace: suggestion.workspace,
        actor: actor,
        recipient: suggestion.user,
        notifiable: suggestion,
        notification_type: Notification::TYPE_KNOWLEDGE_SUGGESTION_READY,
        metadata: {
          "knowledge_suggestion_id" => suggestion.id,
          "kind" => suggestion.kind,
          "title" => suggestion.title,
          "summary" => suggestion.summary,
          "workspace_slug" => suggestion.workspace.slug
        }
      )
    end

    private

    attr_reader :suggestion, :actor
  end
end
