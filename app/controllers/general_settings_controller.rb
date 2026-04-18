class GeneralSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
  end

  def update
    authorize @workspace, :update?

    if @workspace.update(general_settings_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "General settings updated.") }
        format.html do
          redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug, settings_workspace_slug: @workspace.slug),
                      notice: "General settings updated."
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: settings_flash_stream("alert", @workspace.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
        format.html do
          redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug, settings_workspace_slug: @workspace.slug),
                      alert: @workspace.errors.full_messages.to_sentence
        end
      end
    end
  end

  def destroy
    authorize @workspace, :destroy?

    unless destroy_confirmation_valid?
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug, settings_workspace_slug: @workspace.slug),
                  alert: "Type the workspace name exactly to confirm deletion."
      return
    end

    workspace_name = @workspace.name
    if @workspace.update(archived_at: Time.current)
      redirect_to root_path, notice: "#{workspace_name} was archived."
    else
      redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug, settings_workspace_slug: @workspace.slug), alert: @workspace.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    slug = params[:settings_workspace_slug].presence || params[:workspace_slug]
    @workspace = policy_scope(Workspace).find_by!(slug: slug)
  end

  def general_settings_params
    params.fetch(:workspace, {}).permit(:name, :workspace_color, :analytics_enabled, :shell_status_bar_mode)
  end

  def destroy_confirmation_valid?
    params.fetch(:workspace, {}).fetch(:confirm_name, "").to_s == @workspace.name
  end
end
