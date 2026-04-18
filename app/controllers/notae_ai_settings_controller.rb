class NotaeAiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user
  before_action :set_agent_policy

  def show
    authorize @workspace, :show?
    authorize @user, :update?
  end

  def update
    authorize @workspace, agent_policy_submission? ? :update? : :show?
    authorize @user, :update? unless agent_policy_submission?

    if agent_policy_submission?
      if @agent_policy.update(agent_policy_params)
        redirect_to workspace_notae_ai_settings_path(workspace_slug: @workspace.slug), notice: "Agent action policy updated."
      else
        redirect_to workspace_notae_ai_settings_path(workspace_slug: @workspace.slug), alert: @agent_policy.errors.full_messages.to_sentence
      end
    elsif @user.update(notae_ai_setting_params)
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

  def set_agent_policy
    @agent_policy =
      if data_source_available?("agent_policies")
        @workspace.agent_policy || @workspace.build_agent_policy
      else
        AgentPolicy.new(workspace: @workspace)
      end
  end

  def notae_ai_setting_params
    params.fetch(:user, {}).permit(
      :ai_loader_style,
      :ai_search_daily_budget_usd,
      :ai_search_semantic_rate_limit_per_minute,
      :ai_search_answer_rate_limit_per_minute
    )
  end

  def agent_policy_params
    params.fetch(:agent_policy, {}).permit(
      :approval_required,
      :dry_run_required,
      :max_estimated_cost_usd,
      :allow_internal_automation,
      :automation_retry_limit,
      :automation_confidence_threshold,
      allowed_target_systems_json: [],
      allowed_draft_types_json: [],
      approval_required_draft_types_json: [],
      allowed_lifecycle_operations_json: [],
      allowed_internal_actions_json: [],
      author_roles_json: [],
      approver_roles_json: []
    )
  end

  def agent_policy_submission?
    params.key?(:agent_policy)
  end
end
