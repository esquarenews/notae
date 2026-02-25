class NotificationSettingsController < ApplicationController
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

    if @user.update(notification_setting_params)
      redirect_to workspace_notification_settings_path(workspace_slug: @workspace.slug), notice: "Notification settings updated."
    else
      redirect_to workspace_notification_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def notification_setting_params
    params.fetch(:user, {}).permit(
      :meeting_notify_join_transcribing,
      :meeting_notify_transcribed,
      :meeting_notify_summarized,
      :slack_notification_preference,
      :discord_notification_preference,
      :email_notify_activity,
      :email_notify_always_send,
      :email_notify_page_updates,
      :email_notify_workspace_digest
    )
  end
end
