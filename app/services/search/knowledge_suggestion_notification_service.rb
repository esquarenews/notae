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
        metadata: notification_metadata
      )
    end

    private

    attr_reader :suggestion, :actor

    def notification_metadata
      metadata = {
        "knowledge_suggestion_id" => suggestion.id,
        "kind" => suggestion.kind,
        "title" => suggestion.title,
        "summary" => suggestion.summary,
        "workspace_slug" => suggestion.workspace.slug
      }

      metadata.merge!(daily_agenda_metadata) if suggestion.kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY
      metadata
    end

    def daily_agenda_metadata
      Notifications::DailyAgendaBuilder.new(
        user: suggestion.user,
        workspace: suggestion.workspace,
        date: suggestion.generated_for_date.presence || current_local_date
      ).call
    end

    def current_local_date
      Time.use_zone(suggestion.user.time_zone.presence || Time.zone) { Date.current }
    end
  end
end
