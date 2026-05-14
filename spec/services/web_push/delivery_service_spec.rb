require "rails_helper"

RSpec.describe WebPush::DeliveryService do
  it "sends a push payload and records successful delivery state" do
    user = User.create!(email: "web-push-delivery@example.com", password: "password123")
    workspace = Workspace.create!(name: "Push delivery", slug: "web-push-delivery")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://fcm.googleapis.com/subscriptions/ok",
      p256dh: "p256dh-ok",
      auth: "auth-ok"
    )
    notification = Notification.create!(
      workspace: workspace,
      actor: user,
      recipient: user,
      notification_type: Notification::TYPE_CODEX_REQUEST_COMPLETED,
      metadata: { "title" => "Delivery complete", "body" => "Job finished" }
    )

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::Configuration).to receive(:vapid_options).and_return(
      { subject: "mailto:test@example.com", public_key: "public", private_key: "private" }
    )
    expect(::Webpush).to receive(:payload_send).with(
      hash_including(
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth,
        vapid: hash_including(:subject, :public_key, :private_key)
      )
    )

    result = described_class.new(subscription: subscription, payload: { title: "Notae", body: "Body" }, notification: notification).call

    expect(result).to eq(true)
    expect(subscription.reload.last_delivered_at).to be_present
    expect(subscription.last_error_at).to be_nil
    attempt = WebPushDeliveryAttempt.order(:created_at).last
    expect(attempt.status).to eq("delivered")
    expect(attempt.user).to eq(user)
    expect(attempt.workspace).to eq(workspace)
    expect(attempt.notification).to eq(notification)
    expect(attempt.endpoint_host).to eq("fcm.googleapis.com")
    expect(attempt.title).to eq("Notae")
    expect(attempt.body).to eq("Body")
    expect(attempt.delivered_at).to be_present
  end

  it "removes stale subscriptions when the push provider says they expired" do
    user = User.create!(email: "web-push-delivery-stale@example.com", password: "password123")
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://fcm.googleapis.com/subscriptions/stale",
      p256dh: "p256dh-stale",
      auth: "auth-stale"
    )

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::Configuration).to receive(:vapid_options).and_return(
      { subject: "mailto:test@example.com", public_key: "public", private_key: "private" }
    )
    allow(::Webpush).to receive(:payload_send).and_raise(StandardError, "410 gone")

    described_class.new(subscription: subscription, payload: { title: "Notae" }).call

    expect(WebPushSubscription.exists?(subscription.id)).to eq(false)
    attempt = WebPushDeliveryAttempt.order(:created_at).last
    expect(attempt.status).to eq("stale_subscription")
    expect(attempt.endpoint_host).to eq("fcm.googleapis.com")
    expect(attempt.error_message).to include("410 gone")
  end

  it "records non-stale delivery failures without deleting the subscription" do
    user = User.create!(email: "web-push-delivery-failed@example.com", password: "password123")
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://fcm.googleapis.com/subscriptions/fail",
      p256dh: "p256dh-fail",
      auth: "auth-fail"
    )

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::Configuration).to receive(:vapid_options).and_return(
      { subject: "mailto:test@example.com", public_key: "public", private_key: "private" }
    )
    allow(::Webpush).to receive(:payload_send).and_raise(StandardError, "temporary outage")

    result = described_class.new(subscription: subscription, payload: { title: "Notae" }).call

    expect(result).to eq(false)
    expect(subscription.reload.last_error_message).to include("temporary outage")
    expect(WebPushSubscription.exists?(subscription.id)).to eq(true)
    attempt = WebPushDeliveryAttempt.order(:created_at).last
    expect(attempt.status).to eq("failed")
    expect(attempt.error_message).to include("temporary outage")
  end
end
