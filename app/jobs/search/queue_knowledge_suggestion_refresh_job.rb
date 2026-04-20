module Search
  class QueueKnowledgeSuggestionRefreshJob < ApplicationJob
    queue_as :default

    DAILY_BRIEF_WINDOW_HOUR = 7
    PROACTIVE_BUSINESS_HOURS = 9...18

    def perform(workspace_id)
      workspace = Workspace.find_by(id: workspace_id)
      return if workspace.blank?

      workspace.users.distinct.find_each do |user|
        next unless user.openai_api_key_configured?

        queue_due_generation_for(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY)
        queue_due_generation_for(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE)
      end
    end

    private

    def queue_due_generation_for(user:, workspace:, kind:)
      return unless generation_due?(user: user, workspace: workspace, kind: kind)
      return unless Search::PersistKnowledgeSuggestionService.generation_context_available?(user: user, workspace: workspace, kind: kind)

      Search::KnowledgeSuggestionGenerationTracker.mark_pending!(user: user, workspace: workspace, kind: kind)
      Search::GenerateKnowledgeSuggestionJob.perform_later(user.id, workspace.id, kind)
    rescue StandardError => error
      Search::KnowledgeSuggestionGenerationTracker.clear!(user: user, workspace: workspace, kind: kind)
      log_enqueue_failure(user: user, workspace: workspace, kind: kind, error: error)
    end

    def generation_due?(user:, workspace:, kind:)
      return false if Search::KnowledgeSuggestionGenerationTracker.pending?(user: user, workspace: workspace, kind: kind)

      case kind.to_s
      when KnowledgeSuggestion::KIND_DAILY_SUMMARY
        daily_summary_due?(user: user, workspace: workspace)
      when KnowledgeSuggestion::KIND_PROACTIVE
        proactive_due?(user: user, workspace: workspace)
      else
        false
      end
    end

    def daily_summary_due?(user:, workspace:)
      return false if user_local_time(user).hour < DAILY_BRIEF_WINDOW_HOUR

      KnowledgeSuggestion.for_user(user)
        .for_workspace(workspace)
        .daily_summaries
        .where(generated_for_date: current_local_date(user))
        .none?
    end

    def proactive_due?(user:, workspace:)
      return false unless PROACTIVE_BUSINESS_HOURS.cover?(user_local_time(user).hour)

      KnowledgeSuggestion.for_user(user)
        .for_workspace(workspace)
        .active
        .proactive
        .none?
    end

    def user_local_time(user)
      Time.current.in_time_zone(user.time_zone.presence || Time.zone)
    end

    def current_local_date(user)
      user_local_time(user).to_date
    end

    def log_enqueue_failure(user:, workspace:, kind:, error:)
      Rails.logger.error(
        "[KnowledgeSuggestionRefresh] Failed to enqueue #{kind} for workspace=#{workspace.id} user=#{user.id}: #{error.class}: #{error.message}"
      )

      return unless ActiveRecord::Base.connection.data_source_exists?("ai_usage_logs")

      Search::AiUsageLogger.log_outcome!(
        user: user,
        workspace: workspace,
        operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE,
        model: "background_job",
        metadata: {
          kind: kind,
          stage: "refresh_enqueue",
          error_class: error.class.name,
          error_message: error.message.to_s.first(300)
        }
      )
    rescue StandardError => logging_error
      Rails.logger.warn(
        "[KnowledgeSuggestionRefresh] Failed to log enqueue failure for workspace=#{workspace.id} user=#{user.id}: #{logging_error.class}: #{logging_error.message}"
      )
    end
  end
end
