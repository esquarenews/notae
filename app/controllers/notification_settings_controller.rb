class NotificationSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?

    @workspace_membership = current_user.memberships.find_by(workspace_id: @workspace.id)
    @push_delivery_schema_available = push_delivery_schema_available?
    @push_subscriptions =
      if push_subscription_schema_available?
        with_optional_schema_fallback(default: [], feature: "push subscriptions") do
          current_user.web_push_subscriptions.order(created_at: :desc).limit(10).to_a
        end
      else
        []
      end
    @web_push_delivery_attempts =
      if web_push_delivery_attempt_schema_available?
        with_optional_schema_fallback(default: [], feature: "web push delivery attempts") do
          current_user.web_push_delivery_attempts.recent_first.includes(:workspace).limit(12).to_a
        end
      else
        []
      end
  end

  def update
    authorize @workspace, :show?
    authorize @user, :update?

    ActiveRecord::Base.transaction do
      @user.update!(notification_setting_params.merge(push_notification_preferences_payload))
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

    return render json: { ok: false, error: "Push subscription storage is not available on this server yet." }, status: :service_unavailable unless push_subscription_schema_available?
    return render json: { ok: false, error: "Push notifications are not configured on this server yet." }, status: :service_unavailable unless WebPush::Configuration.configured?

    subscriptions = current_user.web_push_subscriptions.order(created_at: :desc).to_a
    return render json: { ok: false, error: "No devices are subscribed for push notifications yet." }, status: :unprocessable_entity if subscriptions.empty?

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
        "endpoint" => test_push_endpoint
      }
    )

    payload = WebPush::NotificationPayloadBuilder.new(notification: notification).call
    current_endpoint = test_push_endpoint
    current_device_delivered = false
    delivered_subscription_count = 0
    current_subscription_seen = false
    current_subscription_stale = false
    error_messages = []

    subscriptions.each do |subscription|
      delivered = WebPush::DeliveryService.new(
        subscription: subscription,
        payload: payload,
        notification: notification
      ).call

      delivered_subscription_count += 1 if delivered

      next unless current_endpoint.present? && subscription.endpoint == current_endpoint

      current_subscription_seen = true
      current_device_delivered = delivered
      current_subscription_stale = !delivered && !WebPushSubscription.exists?(subscription.id)
    end

    subscriptions.each do |subscription|
      next unless WebPushSubscription.exists?(subscription.id)

      error_message = subscription.reload.last_error_message.presence
      error_messages << error_message if error_message.present?
    end

    if delivered_subscription_count.positive?
      render json: {
        ok: true,
        message: "Test push sent to #{ActionController::Base.helpers.pluralize(delivered_subscription_count, 'device')}.",
        notification_id: notification.id,
        current_device_delivered: current_device_delivered,
        delivered_subscription_count: delivered_subscription_count
      }
    else
      if current_subscription_seen && current_subscription_stale
        return render json: {
          ok: false,
          error: "This device subscription expired and needs to be refreshed.",
          error_code: "stale_subscription"
        }, status: :unprocessable_entity
      end

      render json: {
        ok: false,
        error: error_messages.first || "Test push could not be delivered to any device.",
        error_code: "delivery_failed"
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
    permitted_keys = [
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
    ].select { |key| User.column_names.include?(key.to_s) }

    params.fetch(:user, ActionController::Parameters.new).permit(*permitted_keys)
  end

  def test_push_endpoint
    params[:endpoint].to_s.strip
  end

  def merged_push_notification_preferences
    return @user.push_notification_preferences unless push_delivery_preferences_available?

    submitted_preferences = push_notification_preferences_params
    return @user.push_notification_preferences if submitted_preferences.empty?

    @user.push_notification_preferences.merge(submitted_preferences)
  end

  def push_notification_preferences_payload
    return {} unless push_delivery_preferences_available?

    { push_notification_preferences: merged_push_notification_preferences }
  end

  def push_notification_preferences_params
    return {} unless push_delivery_preferences_available?

    permitted = params.fetch(:user, ActionController::Parameters.new).permit(*User.push_notification_param_keys)
    permitted.to_h.each_with_object({}) do |(param_key, raw_value), preferences|
      notification_type = User.push_notification_type_for_param(param_key)
      next unless notification_type

      preferences[notification_type] = ActiveModel::Type::Boolean.new.cast(raw_value)
    end
  end

  def update_workspace_notification_preferences!
    membership_params = workspace_notification_setting_params
    return if membership_params.empty?
    return unless Membership.column_names.include?("notification_preferences_json")

    membership = current_user.memberships.find_by!(workspace_id: @workspace.id)
    preferences = membership.notification_preferences.deep_dup
    if membership_params.key?(:email_notify_activity)
      email_enabled = ActiveModel::Type::Boolean.new.cast(membership_params[:email_notify_activity])
      if email_enabled == @user.email_notify_activity?
        preferences.delete("email_notify_activity")
      else
        preferences["email_notify_activity"] = email_enabled
      end
    end

    push_overrides = preferences["push_notification_preferences"].is_a?(Hash) ? preferences["push_notification_preferences"].deep_dup : {}
    workspace_push_notification_preferences_params(membership_params).each do |notification_type, enabled|
      if enabled == @user.push_notification_enabled_for?(notification_type)
        push_overrides.delete(notification_type)
      else
        push_overrides[notification_type] = enabled
      end
    end

    if push_overrides.empty?
      preferences.delete("push_notification_preferences")
    else
      preferences["push_notification_preferences"] = push_overrides
    end

    membership.update!(notification_preferences_json: preferences)
  end

  def workspace_notification_setting_params
    permitted_keys = [ :email_notify_activity ]
    permitted_keys.concat(User.push_notification_param_keys) if push_delivery_preferences_available?

    params.fetch(:membership, ActionController::Parameters.new).permit(*permitted_keys)
  end

  def workspace_push_notification_preferences_params(membership_params)
    membership_params.to_h.each_with_object({}) do |(param_key, raw_value), preferences|
      notification_type = User.push_notification_type_for_param(param_key)
      next unless notification_type

      preferences[notification_type] = ActiveModel::Type::Boolean.new.cast(raw_value)
    end
  end

  def push_delivery_schema_available?
    push_subscription_schema_available? && web_push_delivery_attempt_schema_available? && push_delivery_preferences_available?
  end

  def push_subscription_schema_available?
    data_source_available?("web_push_subscriptions")
  end

  def web_push_delivery_attempt_schema_available?
    data_source_available?("web_push_delivery_attempts")
  end

  def push_delivery_preferences_available?
    User.column_names.include?("push_notification_preferences") &&
      User.column_names.include?("push_quiet_hours_enabled") &&
      User.column_names.include?("push_quiet_hours_starts_at") &&
      User.column_names.include?("push_quiet_hours_ends_at") &&
      Membership.column_names.include?("notification_preferences_json")
  end
end
