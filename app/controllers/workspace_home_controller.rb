class WorkspaceHomeController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
    @invitation = Invitation.new
    @new_page = Page.new
    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @pages = policy_scope(Page).for_workspace(@workspace).active.order(:created_at).to_a
    @pages_by_parent = @pages.group_by(&:parent_page_id)
    @can_invite = policy(Invitation.new(workspace: @workspace)).create?
    @can_manage_memberships = @memberships.any? { |membership| policy(membership).update? }
    @audit_events = policy_scope(AuditEvent).where(workspace_id: @workspace.id).recent_first.limit(15)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
