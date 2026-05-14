require "rails_helper"

RSpec.describe "PWA push subscriptions", type: :request do
  it "creates or updates the current user's push subscription" do
    user = User.create!(email: "pwa-push-create@example.com", password: "password123")
    sign_in user

    post pwa_push_subscription_path,
         params: {
           subscription: {
             endpoint: "https://fcm.googleapis.com/subscriptions/abc",
             expiration_time: 1_800_000_000_000,
             keys: {
               p256dh: "p256dh-token",
               auth: "auth-token"
             }
           }
         },
         as: :json

    expect(response).to have_http_status(:ok)
    subscription = user.web_push_subscriptions.find_by!(endpoint: "https://fcm.googleapis.com/subscriptions/abc")
    expect(subscription.p256dh).to eq("p256dh-token")
    expect(subscription.auth).to eq("auth-token")
    expect(subscription.expiration_time).to be_present
  end

  it "clears stale delivery errors when a device refreshes an existing subscription" do
    user = User.create!(email: "pwa-push-refresh@example.com", password: "password123")
    subscription = user.web_push_subscriptions.create!(
      endpoint: "https://fcm.googleapis.com/subscriptions/existing",
      p256dh: "old-p256dh-token",
      auth: "old-auth-token",
      last_error_at: 5.minutes.ago,
      last_error_message: "Webpush::ResponseError: 403 Forbidden"
    )
    sign_in user

    post pwa_push_subscription_path,
         params: {
           subscription: {
             endpoint: subscription.endpoint,
             expiration_time: 1_800_000_000_000,
             keys: {
               p256dh: "new-p256dh-token",
               auth: "new-auth-token"
             }
           }
         },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(subscription.reload.p256dh).to eq("new-p256dh-token")
    expect(subscription.auth).to eq("new-auth-token")
    expect(subscription.last_error_at).to be_nil
    expect(subscription.last_error_message).to be_nil
  end

  it "removes the current user's push subscription by endpoint" do
    user = User.create!(email: "pwa-push-destroy@example.com", password: "password123")
    subscription = WebPushSubscription.create!(
      user: user,
      endpoint: "https://fcm.googleapis.com/subscriptions/remove",
      p256dh: "p256dh-remove",
      auth: "auth-remove"
    )
    sign_in user

    delete pwa_push_subscription_path,
           params: { endpoint: subscription.endpoint },
           as: :json

    expect(response).to have_http_status(:no_content)
    expect(WebPushSubscription.exists?(subscription.id)).to eq(false)
  end
end
