require "rails_helper"

RSpec.describe "Email unsubscribes", type: :request do
  it "turns off global activity email notifications from a signed token" do
    user = User.create!(email: "unsubscribe@example.com", password: "password123", email_notify_activity: true)
    token = user.signed_id(purpose: :email_unsubscribe, expires_in: 90.days)

    get email_unsubscribe_path(token: token)

    expect(response).to redirect_to(root_path)
    expect(user.reload.email_notify_activity).to eq(false)
  end

  it "adds list unsubscribe headers to notification mail" do
    actor = User.create!(email: "actor@example.com", password: "password123")
    recipient = User.create!(email: "recipient@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mailer Workspace", slug: "mailer-workspace")
    page = Page.create!(workspace: workspace, title: "Mailer Page", created_by: actor)
    comment = Comment.create!(workspace: workspace, commentable: page, author: actor, body: "Hello")
    notification = Notification.create!(
      workspace: workspace,
      actor: actor,
      recipient: recipient,
      notification_type: Notification::TYPE_MENTION,
      notifiable: comment
    )

    email = NotificationMailer.with(notification: notification, mailer_user: actor).mention_notification

    expect(email.header["List-Unsubscribe"].to_s).to include("/email/unsubscribe/")
    expect(email.header["List-Unsubscribe-Post"].to_s).to include("List-Unsubscribe=One-Click")
  end
end
