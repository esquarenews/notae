class AiAnalyticsSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?

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
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
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
