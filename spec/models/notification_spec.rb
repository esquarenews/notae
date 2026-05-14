require "rails_helper"

RSpec.describe Notification, type: :model do
  include ActiveJob::TestHelper

  around do |example|
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
  ensure
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it "marks notifications as read" do
    actor = User.create!(email: "notif-actor@example.com", password: "password123")
    recipient = User.create!(email: "notif-recipient@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notifications", slug: "notifications")
    notification = described_class.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: "mention",
      metadata: {}
    )

    notification.mark_as_read!

    expect(notification.reload.read_at).to be_present
  end

  it "enqueues web push delivery when the recipient has a subscription and push is configured" do
    actor = User.create!(email: "notif-actor-push@example.com", password: "password123")
    recipient = User.create!(email: "notif-recipient-push@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notifications Push", slug: "notifications-push")
    WebPushSubscription.create!(
      user: recipient,
      endpoint: "https://fcm.googleapis.com/subscriptions/1",
      p256dh: "p256dh-token",
      auth: "auth-token"
    )

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)

    expect {
      described_class.create!(
        workspace: workspace,
        actor: actor,
        recipient: recipient,
        notification_type: described_class::TYPE_MENTION,
        metadata: {}
      )
    }.to have_enqueued_job(WebPush::DeliverNotificationJob)
  end
end
