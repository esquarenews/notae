require "rails_helper"

RSpec.describe WebPush::DeliverNotificationJob do
  it "fans a notification out to each registered subscription" do
    actor = User.create!(email: "web-push-job-actor@example.com", password: "password123")
    recipient = User.create!(email: "web-push-job-recipient@example.com", password: "password123")
    workspace = Workspace.create!(name: "Web Push Job", slug: "web-push-job")
    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )
    first_subscription = WebPushSubscription.create!(
      user: recipient,
      endpoint: "https://push.example.test/subscriptions/a",
      p256dh: "p256dh-a",
      auth: "auth-a"
    )
    second_subscription = WebPushSubscription.create!(
      user: recipient,
      endpoint: "https://push.example.test/subscriptions/b",
      p256dh: "p256dh-b",
      auth: "auth-b"
    )
    payload = { title: "Notae", body: "Mention", url: "/app" }
    payload_builder = instance_double(WebPush::NotificationPayloadBuilder, call: payload)
    first_delivery = instance_double(WebPush::DeliveryService, call: true)
    second_delivery = instance_double(WebPush::DeliveryService, call: true)

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::NotificationPayloadBuilder).to receive(:new).with(notification: notification).and_return(payload_builder)
    expect(WebPush::DeliveryService).to receive(:new).with(subscription: first_subscription, payload: payload).and_return(first_delivery)
    expect(WebPush::DeliveryService).to receive(:new).with(subscription: second_subscription, payload: payload).and_return(second_delivery)

    described_class.perform_now(notification.id)
  end
end
