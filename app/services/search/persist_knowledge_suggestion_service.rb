module Search
  class PersistKnowledgeSuggestionService
    PROACTIVE_INTERVAL = 6.hours
    PROACTIVE_EXPIRY = 6.hours

    def initialize(user:, workspace:, kind:, force: false)
      @user = user
      @workspace = workspace
      @kind = kind.to_s
      @force = force
    end

    def call
      return existing_daily_summary if daily_summary? && !force?
      return active_recent_proactive if proactive? && !force? && active_recent_proactive.present?

      response = Search::KnowledgeSuggestionService.new(
        user: user,
        workspace: workspace,
        mode: suggestion_mode,
        since: proactive_recent_since,
        previous_report: latest_report
      ).call
      return nil if response.blank?

      ActiveRecord::Base.transaction do
        suggestion, created = upsert_suggestion!(response)
        conversation = record_ai_conversation!(suggestion, response)
        suggestion.update!(ai_conversation: conversation) if conversation.present? && suggestion.ai_conversation_id != conversation.id
        notify_suggestion_ready!(suggestion) if created
        suggestion
      end
    end

    def self.ensure_daily_summary!(user:, workspace:)
      new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY).call
    end

    def self.ensure_proactive!(user:, workspace:)
      new(user: user, workspace: workspace, kind: KnowledgeSuggestion::KIND_PROACTIVE).call
    end

    private

    attr_reader :user, :workspace, :kind

    def force?
      @force
    end

    def daily_summary?
      kind == KnowledgeSuggestion::KIND_DAILY_SUMMARY
    end

    def proactive?
      kind == KnowledgeSuggestion::KIND_PROACTIVE
    end

    def existing_daily_summary
      policy_scope_scope.find_by(kind: KnowledgeSuggestion::KIND_DAILY_SUMMARY, generated_for_date: current_local_date)
    end

    def active_recent_proactive
      policy_scope_scope.active.proactive.recent_first.first
    end

    def policy_scope_scope
      KnowledgeSuggestion.for_user(user).for_workspace(workspace)
    end

    def upsert_suggestion!(response)
      record =
        if daily_summary?
          policy_scope_scope.find_or_initialize_by(kind: kind, generated_for_date: current_local_date)
        else
          policy_scope_scope.new(kind: kind)
        end
      created = record.new_record?

      record.assign_attributes(
        status: KnowledgeSuggestion::STATUS_ACTIVE,
        title: title_for(response),
        summary: response.summary,
        insights_json: response.insights,
        task_suggestions_json: response.task_suggestions,
        related_notes_json: response.related_notes,
        sources_json: response.sources,
        metadata_json: suggestion_metadata_for(response),
        generated_at: Time.current,
        expires_at: proactive? ? PROACTIVE_EXPIRY.from_now : nil,
        dismissed_at: nil,
        converted_at: nil
      )
      record.save!
      [ record, created ]
    end

    def record_ai_conversation!(suggestion, response)
      AiConversation.create!(
        user: user,
        workspace: workspace,
        scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
        status: AiConversation::STATUS_SUGGESTION,
        prompt: prompt_label,
        answer: render_conversation_answer(suggestion: suggestion, response: response),
        sources: response.sources,
        model: response.model
      )
    rescue ActiveRecord::RecordInvalid => error
      Rails.logger.warn("Knowledge suggestion conversation persist failed workspace=#{workspace.id}: #{error.message}")
      nil
    end

    def prompt_label
      daily_summary? ? "Daily morning summary" : "Proactive workspace suggestion"
    end

    def current_local_date
      Time.use_zone(user.time_zone.presence || Time.zone) { Date.current }
    end

    def title_for(response)
      return "Daily morning summary" if daily_summary?

      task_title = Array(response.task_suggestions).first&.fetch("title", nil).to_s.strip
      task_title.presence || (response.report_mode == Search::KnowledgeSuggestionService::MODE_DELTA ? "What's changed" : "Suggested next step")
    end

    def render_conversation_answer(suggestion:, response:)
      sections = []
      sections << suggestion.summary.to_s.strip
      insights = Array(response.insights).map { |item| "- #{item}" }
      sections << [ "Insights", insights.join("\n") ].join("\n") if insights.any?
      tasks = Array(response.task_suggestions).map do |item|
        title = item["title"].to_s.strip
        owner = item["owner"].to_s.strip.presence
        rationale = item["rationale"].to_s.strip
        line = "- #{title}"
        line += " (owner: #{owner})" if owner.present?
        line += " — #{rationale}" if rationale.present?
        line
      end
      sections << [ "Task suggestions", tasks.join("\n") ].join("\n") if tasks.any?
      sections.join("\n\n")
    end

    def suggestion_mode
      proactive? ? Search::KnowledgeSuggestionService::MODE_DELTA : Search::KnowledgeSuggestionService::MODE_FULL
    end

    def latest_report
      return nil unless proactive?

      @latest_report ||= policy_scope_scope.recent_first.first
    end

    def proactive_recent_since
      return nil unless proactive?

      [ latest_report&.generated_at, PROACTIVE_INTERVAL.ago ].compact.max
    end

    def suggestion_metadata_for(response)
      metadata = {
        "model" => response.model,
        "report_mode" => response.report_mode
      }
      metadata["baseline_generated_at"] = response.baseline_generated_at&.iso8601 if response.baseline_generated_at.present?
      metadata["recent_since"] = response.recent_since&.iso8601 if response.recent_since.present?
      metadata["context_snapshot"] = response.context_snapshot if response.context_snapshot.present?
      metadata
    end

    def notify_suggestion_ready!(suggestion)
      Search::KnowledgeSuggestionNotificationService.new(suggestion: suggestion, actor: user).notify_ready!
    end
  end
end
