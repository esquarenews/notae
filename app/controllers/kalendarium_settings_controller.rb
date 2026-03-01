class KalendariumSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @connections = policy_scope(KalendariumConnection).for_workspace(@workspace).includes(:kalendarium_calendars).order(created_at: :desc)
    @calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).order(:name)
    @time_zone_options = User.time_zone_options
  end

  def update
    authorize @workspace, :show?
    authorize current_user, :update?

    time_zones = Array(settings_params[:calendar_extra_time_zones]).map(&:to_s).reject(&:blank?).uniq
    if current_user.update(calendar_extra_time_zones: time_zones)
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Kalendarium settings updated."
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: current_user.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def settings_params
    params.fetch(:user, {}).permit(calendar_extra_time_zones: [])
  end
end
