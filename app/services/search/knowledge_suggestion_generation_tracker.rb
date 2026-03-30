module Search
  class KnowledgeSuggestionGenerationTracker
    DAILY_TTL = 45.minutes
    PROACTIVE_TTL = 15.minutes

    class << self
      def pending?(user:, workspace:, kind:)
        Rails.cache.exist?(cache_key_for(user: user, workspace: workspace, kind: kind))
      end

      def mark_pending!(user:, workspace:, kind:)
        Rails.cache.write(
          cache_key_for(user: user, workspace: workspace, kind: kind),
          true,
          expires_in: ttl_for(kind)
        )
      end

      def clear!(user:, workspace:, kind:)
        Rails.cache.delete(cache_key_for(user: user, workspace: workspace, kind: kind))
      end

      private

      def cache_key_for(user:, workspace:, kind:)
        parts = [
          "knowledge_suggestion_generation",
          kind.to_s,
          user.id,
          workspace.id
        ]
        parts << current_local_date_for(user).iso8601 if kind.to_s == KnowledgeSuggestion::KIND_DAILY_SUMMARY
        parts.join(":")
      end

      def current_local_date_for(user)
        Time.use_zone(user.time_zone.presence || Time.zone) { Date.current }
      end

      def ttl_for(kind)
        kind.to_s == KnowledgeSuggestion::KIND_DAILY_SUMMARY ? DAILY_TTL : PROACTIVE_TTL
      end
    end
  end
end
