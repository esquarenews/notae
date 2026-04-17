class WorkspaceNotificationBarsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    presenter = WorkspaceNotificationBarPresenter.new(
      workspace: @workspace,
      user: current_user,
      reference_time: Time.zone.now
    )

    render json: {
      data: {
        has_alerts: presenter.has_alerts?,
        html: render_to_string(
          partial: "shared/workspace_notification_bar_alerts",
          formats: [ :html ],
          locals: { presenter: presenter, workspace: @workspace }
        )
      }
    }
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
