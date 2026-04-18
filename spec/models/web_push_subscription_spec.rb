require "rails_helper"

RSpec.describe WebPushSubscription, type: :model do
  it "requires a unique endpoint and subscription keys" do
    user = User.create!(email: "web-push-subscription@example.com", password: "password123")
    described_class.create!(
      user: user,
      endpoint: "https://push.example.test/subscriptions/1",
      p256dh: "p256dh-token",
      auth: "auth-token"
    )

    duplicate = described_class.new(
      user: user,
      endpoint: "https://push.example.test/subscriptions/1",
      p256dh: "",
      auth: ""
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:endpoint]).to include("has already been taken")
    expect(duplicate.errors[:p256dh]).to include("can't be blank")
    expect(duplicate.errors[:auth]).to include("can't be blank")
  end

  it "reports host and delivery health for diagnostics" do
    user = User.create!(email: "web-push-diagnostics@example.com", password: "password123")
    subscription = described_class.create!(
      user: user,
      endpoint: "https://web.push.apple.com/QH123/subscriptions/1",
      p256dh: "p256dh-token",
      auth: "auth-token",
      last_error_at: Time.current
    )

    expect(subscription.endpoint_host).to eq("web.push.apple.com")
    expect(subscription.delivery_status).to eq(:failing)

    subscription.update!(last_delivered_at: Time.current + 1.minute)

    expect(subscription.delivery_status).to eq(:healthy)
  end
end
