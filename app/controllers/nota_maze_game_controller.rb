class NotaMazeGameController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
