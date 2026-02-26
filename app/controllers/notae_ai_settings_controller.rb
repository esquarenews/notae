class NotaeAiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user
  before_action :set_ai_usage_panel, only: :show

  def show
    authorize @workspace, :show?
    authorize @user, :update?
  end

  def update
    authorize @workspace, :show?
    authorize @user, :update?

    if @user.update(notae_ai_setting_params)
      redirect_to workspace_notae_ai_settings_path(workspace_slug: @workspace.slug), notice: "Notae AI settings updated."
    else
      redirect_to workspace_notae_ai_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def notae_ai_setting_params
    params.fetch(:user, {}).permit(:ai_loader_style)
  end

  def set_ai_usage_panel
    day_end = Time.current
    day_start = day_end.beginning_of_day
    usage_scope = AiUsageLog.for_user_and_workspace(user: @user, workspace: @workspace).for_day(day_start, day_end)

    prompt_tokens, completion_tokens, total_tokens, estimated_cost_usd, request_count = usage_scope.pick(
      Arel.sql("COALESCE(SUM(prompt_tokens), 0)"),
      Arel.sql("COALESCE(SUM(completion_tokens), 0)"),
      Arel.sql("COALESCE(SUM(total_tokens), 0)"),
      Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"),
      Arel.sql("COUNT(*)")
    )

    daily_budget_usd = Rails.application.config.x.ai_search.daily_budget_usd.to_f
    spent_today = estimated_cost_usd.to_f
    budget_remaining = [ daily_budget_usd - spent_today, 0.0 ].max

    @ai_usage_panel = {
      day_label: day_end.strftime("%b %-d"),
      prompt_tokens: prompt_tokens.to_i,
      completion_tokens: completion_tokens.to_i,
      total_tokens: total_tokens.to_i,
      estimated_cost_usd: spent_today,
      request_count: request_count.to_i,
      budget_status: Search::AiBudgetGuard.within_daily_budget?(user: @user, workspace: @workspace),
      daily_budget_usd: daily_budget_usd,
      budget_remaining_usd: budget_remaining,
      semantic_rate_limit_per_minute: Rails.application.config.x.ai_search.semantic_rate_limit_per_minute.to_i,
      answer_rate_limit_per_minute: Rails.application.config.x.ai_search.answer_rate_limit_per_minute.to_i,
      rate_limit_window_seconds: Rails.application.config.x.ai_search.rate_limit_window_seconds.to_i
    }
  end
end
