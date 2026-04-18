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

  it "skips delivery when the notification type is disabled for the recipient" do
    actor = User.create!(email: "web-push-disabled-actor@example.com", password: "password123")
    recipient = User.create!(
      email: "web-push-disabled-recipient@example.com",
      password: "password123",
      push_notification_preferences: { Notification::TYPE_MENTION => false }
    )
    workspace = Workspace.create!(name: "Web Push Disabled", slug: "web-push-disabled")
    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )
    WebPushSubscription.create!(
      user: recipient,
      endpoint: "https://push.example.test/subscriptions/disabled",
      p256dh: "p256dh-disabled",
      auth: "auth-disabled"
    )

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::NotificationPayloadBuilder).to receive(:new)
    allow(WebPush::DeliveryService).to receive(:new)

    described_class.perform_now(notification.id)

    expect(WebPush::NotificationPayloadBuilder).not_to have_received(:new)
    expect(WebPush::DeliveryService).not_to have_received(:new)
  end

  it "suppresses routine pushes during quiet hours but still delivers workflow failures" do
    actor = User.create!(email: "web-push-quiet-hours-actor@example.com", password: "password123")
    recipient = User.create!(
      email: "web-push-quiet-hours-recipient@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne",
      push_quiet_hours_enabled: true,
      push_quiet_hours_starts_at: "22:00",
      push_quiet_hours_ends_at: "07:00"
    )
    workspace = Workspace.create!(name: "Web Push Quiet Hours", slug: "web-push-quiet-hours")
    mention = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_MENTION,
      metadata: {}
    )
    workflow_failure = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_WORKFLOW_FAILED,
      metadata: {}
    )
    subscription = WebPushSubscription.create!(
      user: recipient,
      endpoint: "https://push.example.test/subscriptions/quiet-hours",
      p256dh: "p256dh-quiet-hours",
      auth: "auth-quiet-hours"
    )
    payload_builder = instance_double(WebPush::NotificationPayloadBuilder, call: { title: "Notae", body: "Workflow failed", url: "/app" })
    delivery = instance_double(WebPush::DeliveryService, call: true)
    within_quiet_hours = Time.find_zone!("Australia/Melbourne").parse("2026-04-18 23:15")

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(Time).to receive(:current).and_return(within_quiet_hours)
    allow(WebPush::NotificationPayloadBuilder).to receive(:new).with(notification: workflow_failure).and_return(payload_builder)
    allow(WebPush::DeliveryService).to receive(:new).with(subscription: subscription, payload: { title: "Notae", body: "Workflow failed", url: "/app" }).and_return(delivery)

    described_class.perform_now(mention.id)
    described_class.perform_now(workflow_failure.id)

    expect(WebPush::NotificationPayloadBuilder).to have_received(:new).once
    expect(WebPush::DeliveryService).to have_received(:new).once
  end
end
