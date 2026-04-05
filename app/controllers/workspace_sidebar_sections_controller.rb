class WorkspaceSidebarSectionsController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show

  def show
    authorize @workspace, :show?

    render partial: "shared/app_sidebar_sections_frame",
           locals: {
             workspace: @workspace,
             lazy: false
           }
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
