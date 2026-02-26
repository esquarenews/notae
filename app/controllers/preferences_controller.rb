class PreferencesController < ApplicationController
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

    if @user.update(preference_params)
      redirect_to workspace_preferences_path(workspace_slug: @workspace.slug), notice: "Preferences updated."
    else
      redirect_to workspace_preferences_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def preference_params
    permitted = params.fetch(:user, {}).permit(
      :theme_preference,
      :language_preference,
      :start_week_preference,
      :show_text_direction_controls,
      :date_format_preference,
      :auto_time_zone,
      :time_zone,
      :open_links_in_desktop_app,
      :open_on_start_preference,
      :reduce_ai_loader_motion,
      :cookie_settings_preference,
      :show_view_history,
      :profile_discoverability
    )

    if permitted.key?(:start_week_preference)
      selected = permitted.delete(:start_week_preference).to_s
      permitted[:start_week_on_monday] = selected != "sunday"
    end

    permitted
  end
end
