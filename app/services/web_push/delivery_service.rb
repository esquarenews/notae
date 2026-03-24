require "webpush"

module WebPush
  class DeliveryService
    def initialize(subscription:, payload:)
      @subscription = subscription
      @payload = payload
    end

    def call
      return false unless WebPush::Configuration.configured?

      ::Webpush.payload_send(
        message: JSON.generate(payload),
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: WebPush::Configuration.vapid_options,
        ttl: 300
      )

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

    attr_reader :subscription, :payload

    def handle_delivery_error(error)
      if stale_subscription_error?(error)
        subscription.destroy!
        return
      end

      subscription.update_columns(
        last_error_at: Time.current,
        last_error_message: "#{error.class}: #{error.message}".truncate(500),
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
  end
end
