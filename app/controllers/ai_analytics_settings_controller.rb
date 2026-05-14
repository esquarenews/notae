class AiAnalyticsSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user
  before_action :set_automation_control

  def show
    authorize @workspace, :show?
    authorize @user, :update?
    refresh_analytics!
  end

  def update
    authorize @workspace, :update?
    authorize_automation_control_update!

    enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:automation_control, :enabled))
    if enabled
      @automation_control.resume!
      notice = "Automation kill switch disabled."
    else
      @automation_control.pause!(reason: params.dig(:automation_control, :pause_reason))
      notice = "Automation kill switch enabled."
    end

    refresh_analytics!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          settings_flash_stream("notice", notice),
          turbo_stream.replace("ai_analytics_settings_content", partial: "ai_analytics_settings/content")
        ]
      end
      format.html { redirect_to workspace_ai_analytics_settings_path(workspace_slug: @workspace.slug), notice: notice }
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def set_automation_control
    @automation_control = AutomationControl.current
  end

  def authorize_automation_control_update!
    raise Pundit::NotAuthorizedError, "not allowed to update automation control" unless current_user&.platform_admin?
  end

  def refresh_analytics!
    usage_scope = AiUsageLog.for_user_and_workspace(user: @user, workspace: @workspace)
    now = Time.current

    @ai_analytics_7_days = daily_series(scope: usage_scope, days: 7, end_time: now)
    @ai_analytics_30_days = daily_series(scope: usage_scope, days: 30, end_time: now)
    @ai_analytics_operations = usage_scope.where(created_at: (now - 30.days)..now)
                                         .group(:operation)
                                         .pluck(
                                           :operation,
                                           Arel.sql("COALESCE(SUM(total_tokens), 0)"),
                                           Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"),
                                           Arel.sql("COUNT(*)")
                                         )
                                         .map do |operation, tokens, cost, count|
      {
        operation: operation,
        tokens: tokens.to_i,
        cost: cost.to_f,
        count: count.to_i
      }
    end
    unless @ai_analytics_operations.any? { |entry| entry[:operation] == AiUsageLog::OP_MEETING_TRANSCRIPTION }
      @ai_analytics_operations << {
        operation: AiUsageLog::OP_MEETING_TRANSCRIPTION,
        tokens: 0,
        cost: 0.0,
        count: 0
      }
    end
    @ai_analytics_operations = @ai_analytics_operations.sort_by { |entry| -entry[:tokens] }

    suggestion_scope = policy_scope(KnowledgeSuggestion).for_workspace(@workspace).where(generated_at: (now - 30.days)..now)
    suggestion_total = suggestion_scope.count
    suggestion_converted = suggestion_scope.where(status: KnowledgeSuggestion::STATUS_CONVERTED).count
    @suggestion_quality_rate = suggestion_total.zero? ? nil : (suggestion_converted.to_f / suggestion_total)
    suggestion_issue_scope = usage_scope.where(
      operation: [
        AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS,
        AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE
      ],
      created_at: (now - 30.days)..now
    )
    @knowledge_suggestion_miss_count = suggestion_issue_scope.where(operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS).count
    @knowledge_suggestion_failure_count = suggestion_issue_scope.where(operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE).count
    @recent_suggestion_issues = suggestion_issue_scope.order(created_at: :desc).limit(10)

    decided_agent_actions = policy_scope(AgentAction)
                              .for_workspace(@workspace)
                              .where(status: [ AgentAction::STATUS_APPROVED, AgentAction::STATUS_REJECTED ])
    approved_agent_actions = decided_agent_actions.where(status: AgentAction::STATUS_APPROVED).count
    decided_count = decided_agent_actions.count
    @approval_rate = decided_count.zero? ? nil : (approved_agent_actions.to_f / decided_count)

    workflow_scope = policy_scope(WorkflowRun).for_workspace(@workspace)
    finished_workflows = workflow_scope.where(status: [ WorkflowRun::STATUS_SUCCEEDED, WorkflowRun::STATUS_FAILED, WorkflowRun::STATUS_KILLED, WorkflowRun::STATUS_CANCELLED ])
    successful_workflows = finished_workflows.where(status: WorkflowRun::STATUS_SUCCEEDED).count
    finished_workflow_count = finished_workflows.count
    @automation_success_rate = finished_workflow_count.zero? ? nil : (successful_workflows.to_f / finished_workflow_count)
    @recent_failed_workflows = workflow_scope.failed.recent_first.limit(10)
  end

  def daily_series(scope:, days:, end_time:)
    start_date = (end_time.to_date - (days - 1))
    sums_by_day = scope.where(created_at: start_date.beginning_of_day..end_time)
                       .group(Arel.sql("DATE(created_at)"))
                       .pluck(
                         Arel.sql("DATE(created_at)"),
                         Arel.sql("COALESCE(SUM(total_tokens), 0)"),
                         Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"),
                         Arel.sql("COUNT(*)")
                       )
                       .to_h do |date, tokens, cost, count|
      [ date.to_date, { tokens: tokens.to_i, cost: cost.to_f, count: count.to_i } ]
    end

    (0...days).map do |index|
      date = start_date + index.days
      totals = sums_by_day[date] || { tokens: 0, cost: 0.0, count: 0 }

      {
        date: date,
        tokens: totals[:tokens],
        cost: totals[:cost],
        count: totals[:count]
      }
    end
  end
end
