class NotificationSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?

    @workspace_membership = current_user.memberships.find_by(workspace_id: @workspace.id)
    @push_subscriptions = current_user.web_push_subscriptions.order(created_at: :desc).limit(10)
  end

  def update
    authorize @workspace, :show?
    authorize @user, :update?

    ActiveRecord::Base.transaction do
      @user.update!(notification_setting_params.merge(push_notification_preferences: merged_push_notification_preferences))
      update_workspace_notification_preferences!
    end

    respond_to do |format|
      format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "Notification settings updated.") }
      format.html { redirect_to workspace_notification_settings_path(workspace_slug: @workspace.slug), notice: "Notification settings updated." }
    end
  rescue ActiveRecord::RecordInvalid => error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: settings_flash_stream("alert", error.record.errors.full_messages.to_sentence),
               status: :unprocessable_entity
      end
      format.html { redirect_to workspace_notification_settings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence }
    end
  end

  def send_test_push
    authorize @workspace, :show?
    authorize @user, :update?

    return render json: { ok: false, error: "Push notifications are not configured on this server yet." }, status: :service_unavailable unless WebPush::Configuration.configured?

    subscription = current_user.web_push_subscriptions.find_by(endpoint: test_push_endpoint)
    return render json: { ok: false, error: "This device is not subscribed for push notifications." }, status: :unprocessable_entity if subscription.blank?

    test_payload = WebPush::TestPayloadBuilder.new(user: current_user, workspace: @workspace).call

    notification = Notification.create!(
      workspace: @workspace,
      actor: current_user,
      recipient: current_user,
      notification_type: Notification::TYPE_TEST_PUSH,
      metadata: {
        "title" => "Notae test notification",
        "body" => test_payload[:body],
        "path" => workspace_notification_settings_path(workspace_slug: @workspace.slug),
        "endpoint" => subscription.endpoint
      }
    )

    delivered = WebPush::DeliveryService.new(
      subscription: subscription,
      payload: WebPush::NotificationPayloadBuilder.new(notification: notification).call
    ).call

    if delivered
      render json: { ok: true, message: "Test push sent to this device.", notification_id: notification.id }
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
      :push_quiet_hours_enabled,
      :push_quiet_hours_starts_at,
      :push_quiet_hours_ends_at,
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

  def merged_push_notification_preferences
    submitted_preferences = push_notification_preferences_params
    return @user.push_notification_preferences if submitted_preferences.empty?

    @user.push_notification_preferences.merge(submitted_preferences)
  end

  def push_notification_preferences_params
    permitted = params.fetch(:user, {}).permit(*User.push_notification_param_keys)
    permitted.to_h.each_with_object({}) do |(param_key, raw_value), preferences|
      notification_type = User.push_notification_type_for_param(param_key)
      next unless notification_type

      preferences[notification_type] = ActiveModel::Type::Boolean.new.cast(raw_value)
    end
  end

  def update_workspace_notification_preferences!
    membership_params = params[:membership]
    return unless membership_params.respond_to?(:[])
    return unless membership_params.key?(:email_notify_activity)

    membership = current_user.memberships.find_by!(workspace_id: @workspace.id)
    preferences = membership.notification_preferences.deep_dup
    preferences["email_notify_activity"] = ActiveModel::Type::Boolean.new.cast(membership_params[:email_notify_activity])
    membership.update!(notification_preferences_json: preferences)
  end
end
