class GeneralSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
  end

  def update
    authorize @workspace, :update?

    if @workspace.update(general_settings_params)
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug), notice: "General settings updated."
    else
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug), alert: @workspace.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @workspace, :destroy?

    unless destroy_confirmation_valid?
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug),
                  alert: "Type the workspace name exactly to confirm deletion."
      return
    end

    workspace_name = @workspace.name
    if @workspace.update(archived_at: Time.current)
      redirect_to root_path, notice: "#{workspace_name} was archived."
    else
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug), alert: @workspace.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def general_settings_params
    params.fetch(:workspace, {}).permit(:name, :workspace_color, :analytics_enabled)
  end

  def destroy_confirmation_valid?
    params.fetch(:workspace, {}).fetch(:confirm_name, "").to_s == @workspace.name
  end
end
