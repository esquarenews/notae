require "webpush"

module WebPush
  class DeliveryService
    def initialize(subscription:, payload:, notification: nil)
      @subscription = subscription
      @payload = payload
      @notification = notification
    end

    def call
      return false unless WebPush::Configuration.configured?
      return blocked_private_endpoint! unless endpoint_public_after_resolution?

      ::Webpush.payload_send(
        message: JSON.generate(payload),
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: WebPush::Configuration.vapid_options,
        ttl: 300,
        open_timeout: 5,
        read_timeout: 10
      )

      record_attempt!(:delivered, delivered_at: Time.current)
      subscription.update_columns(
        last_delivered_at: Time.current,
        last_error_at: nil,
        last_error_message: nil,
        updated_at: Time.current
      )
      true
    rescue StandardError => error
      handle_delivery_error(error)
      false
    end

    private

    attr_reader :subscription, :payload, :notification

    def endpoint_public_after_resolution?
      uri = URI.parse(subscription.endpoint.to_s)
      uri.is_a?(URI::HTTPS) &&
        uri.host.present? &&
        Notae::OutboundNetworkGuard.public_resolved_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def blocked_private_endpoint!
      error_message = "Web push endpoint host resolved to a blocked private or local address"
      record_attempt!(:blocked_endpoint, error_message: error_message)
      subscription.update_columns(
        last_error_at: Time.current,
        last_error_message: error_message,
        updated_at: Time.current
      )
      false
    end

    def handle_delivery_error(error)
      formatted_error = "#{error.class}: #{error.message}".truncate(500)

      if stale_subscription_error?(error)
        record_attempt!(:stale_subscription, error_message: formatted_error)
        subscription.destroy!
        return
      end

      record_attempt!(:failed, error_message: formatted_error)
      subscription.update_columns(
        last_error_at: Time.current,
        last_error_message: formatted_error,
        updated_at: Time.current
      )
      Rails.logger.warn("Web push delivery failed for subscription=#{subscription.id}: #{error.class}: #{error.message}")
    end

    def stale_subscription_error?(error)
      class_name = error.class.name.to_s
      message = error.message.to_s

      class_name.include?("ExpiredSubscription") ||
        class_name.include?("InvalidSubscription") ||
        message.include?("410") ||
        message.include?("404") ||
        message.downcase.include?("invalid subscription")
    end

    def record_attempt!(status, delivered_at: nil, error_message: nil)
      WebPushDeliveryAttempt.create!(
        user: subscription.user,
        workspace: notification&.workspace,
        subscription: subscription,
        notification: notification,
        endpoint_host: subscription.endpoint_host,
        notification_type: notification&.notification_type.to_s.presence || payload[:type].to_s.presence,
        title: payload[:title].to_s,
        body: payload[:body].to_s,
        status: status,
        delivered_at: delivered_at,
        error_message: error_message.to_s
      )
    rescue StandardError => error
      Rails.logger.warn("Web push attempt logging failed for subscription=#{subscription.id}: #{error.class}: #{error.message}")
    end
  end
end
