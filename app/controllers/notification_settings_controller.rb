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

  def send_test_push
    authorize @workspace, :show?
    authorize @user, :update?

    return render json: { ok: false, error: "Push notifications are not configured on this server yet." }, status: :service_unavailable unless WebPush::Configuration.configured?

    subscription = current_user.web_push_subscriptions.find_by(endpoint: test_push_endpoint)
    return render json: { ok: false, error: "This device is not subscribed for push notifications." }, status: :unprocessable_entity if subscription.blank?

    delivered = WebPush::DeliveryService.new(
      subscription: subscription,
      payload: WebPush::TestPayloadBuilder.new(user: current_user, workspace: @workspace).call
    ).call

    if delivered
      render json: { ok: true, message: "Test push sent to this device." }
    else
      render json: {
        ok: false,
        error: subscription.reload.last_error_message.presence || "Test push could not be delivered to this device."
      }, status: :unprocessable_entity
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

  def test_push_endpoint
    params[:endpoint].to_s.strip
  end
end
