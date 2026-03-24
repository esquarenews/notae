require "rails_helper"

RSpec.describe WebPush::DeliveryService do
  it "sends a push payload and records successful delivery state" do
    user = User.create!(email: "web-push-delivery@example.com", password: "password123")
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://push.example.test/subscriptions/ok",
      p256dh: "p256dh-ok",
      auth: "auth-ok"
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

    result = described_class.new(subscription: subscription, payload: { title: "Notae" }).call

    expect(result).to eq(true)
    expect(subscription.reload.last_delivered_at).to be_present
    expect(subscription.last_error_at).to be_nil
  end

  it "removes stale subscriptions when the push provider says they expired" do
    user = User.create!(email: "web-push-delivery-stale@example.com", password: "password123")
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://push.example.test/subscriptions/stale",
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
  end
end
