require "rails_helper"

RSpec.describe NotificationPolicy::Scope do
  it "returns only recipient notifications within visible workspaces" do
    actor = User.create!(email: "notif-pol-actor@example.com", password: "password123")
    recipient = User.create!(email: "notif-pol-recipient@example.com", password: "password123")
    other = User.create!(email: "notif-pol-other@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Policy", slug: "notif-policy")
    other_workspace = Workspace.create!(name: "Notif Other", slug: "notif-other")
    Membership.create!(workspace: workspace, user: recipient, role: :member)
    Membership.create!(workspace: other_workspace, user: recipient, role: :member)
    visible = Notification.create!(workspace: workspace, actor: actor, recipient: recipient, notification_type: "mention", metadata: {})
    hidden = Notification.create!(workspace: other_workspace, actor: actor, recipient: other, notification_type: "mention", metadata: {})

    scope = described_class.new(recipient, Notification.all).resolve

    expect(scope).to include(visible)
    expect(scope).not_to include(hidden)
  end
end
