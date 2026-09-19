class NotificationsController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_notification, only: %i[show mark_read]
  track_request_performance_for :index

  def index
    authorize Notification
    @notifications = policy_scope(Notification).where(workspace_id: @workspace.id).recent_first.limit(100)
  end

  def show
    authorize @notification
    @notification.mark_as_read! if @notification.read_at.blank?
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
