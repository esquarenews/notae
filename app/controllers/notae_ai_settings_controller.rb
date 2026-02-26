class NotaeAiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

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
    params.fetch(:user, {}).permit(
      :ai_loader_style,
      :ai_search_daily_budget_usd,
      :ai_search_semantic_rate_limit_per_minute,
      :ai_search_answer_rate_limit_per_minute
    )
  end
end
