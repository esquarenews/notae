module WebPush
  class DeliverNotificationJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      return unless WebPush::Configuration.configured?

      notification = Notification.includes(:recipient, :workspace, :notifiable).find_by(id: notification_id)
      return if notification.blank?

      payload = WebPush::NotificationPayloadBuilder.new(notification: notification).call
      notification.recipient.web_push_subscriptions.find_each do |subscription|
        WebPush::DeliveryService.new(subscription: subscription, payload: payload).call
      end
    end
  end
end
