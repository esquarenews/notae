require "rails_helper"

RSpec.describe Notification, type: :model do
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
end
