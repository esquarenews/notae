class NotificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_notification, only: :mark_read

  def index
    authorize Notification
    @notifications = policy_scope(Notification).where(workspace_id: @workspace.id).recent_first.limit(100)
  end

  def mark_read
    authorize @notification, :mark_read?
    @notification.mark_as_read!
    redirect_to workspace_notifications_path(workspace_slug: @workspace.slug), notice: "Notification marked as read."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_notification
    @notification = policy_scope(Notification).where(workspace_id: @workspace.id).find(params[:id])
  end
end
