module WebPush
  class DeliverNotificationJob < ApplicationJob
    queue_as :default

    def perform(notification_id)
      return unless WebPush::Configuration.configured?

      notification = Notification.includes(:recipient, :workspace, :notifiable).find_by(id: notification_id)
      return if notification.blank?
      return unless notification.recipient.push_delivery_allowed_for?(notification.notification_type, workspace: notification.workspace)

      payload = WebPush::NotificationPayloadBuilder.new(notification: notification).call
      notification.recipient.web_push_subscriptions.find_each do |subscription|
        WebPush::DeliveryService.new(subscription: subscription, payload: payload).call
      end
    end
  end
end
