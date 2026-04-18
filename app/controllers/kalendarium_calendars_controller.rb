class KalendariumCalendarsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_calendar

  def update
    authorize @calendar

    if @calendar.update(calendar_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "Calendar updated.") }
        format.html { redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Calendar updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: settings_flash_stream("alert", @calendar.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
        format.html { redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: @calendar.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_calendar
    @calendar = policy_scope(KalendariumCalendar).for_workspace(@workspace).find(params[:id])
  end

  def calendar_params
    params.require(:kalendarium_calendar).permit(:enabled, :color_hex, :time_zone, :default_for_projects)
  end
end
