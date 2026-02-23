class WorkspaceHomeController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
    @invitation = Invitation.new
    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @can_invite = policy(Invitation.new(workspace: @workspace)).create?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
