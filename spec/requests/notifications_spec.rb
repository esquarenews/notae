require "rails_helper"

RSpec.describe "Notifications", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs

    perform_enqueued_jobs do
      example.run
    end
  ensure
    ActionMailer::Base.deliveries.clear
    clear_enqueued_jobs
  end

  it "creates mention notifications and updates unread count when read" do
    author = User.create!(email: "mention-author@example.com", password: "password123")
    mentioned = User.create!(email: "mention-target@example.com", password: "password123")
    workspace = Workspace.create!(name: "Mentions", slug: "mentions")
    Membership.create!(workspace: workspace, user: author, role: :owner)
    Membership.create!(workspace: workspace, user: mentioned, role: :member)
    page = Page.create!(workspace: workspace, created_by: author, title: "Mentions Page")

    sign_in author
    post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
         params: { comment: { body: "Please review this @mention-target@example.com" } }
    notification = Notification.where(recipient: mentioned).last
    expect(notification).to be_present
    expect(notification.read_at).to be_nil
    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.last
    expect(mail.to).to eq([ mentioned.email ])
    expect(mail.subject).to include("mentioned you")
    expect(mail.body.encoded).to include("Please review this @mention-target@example.com")

    sign_out author
    sign_in mentioned
    get workspace_notifications_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-utility-page")
    expect(response.body).to include("notae-utility-notification-item")
    expect(response.body).to include("mentioned you")
    expect(response.body).to include("Unread: 1")

    patch read_workspace_notification_path(workspace_slug: workspace.slug, id: notification.id)
    expect(notification.reload.read_at).to be_present

    get workspace_notifications_path(workspace_slug: workspace.slug)
    expect(response.body).to include("Unread: 0")
  end

  it "does not send mention email when recipient disables activity email notifications" do
    author = User.create!(email: "mention-author-no-email@example.com", password: "password123")
    mentioned = User.create!(
      email: "mention-target-no-email@example.com",
      password: "password123",
      email_notify_activity: false
    )
    workspace = Workspace.create!(name: "Mentions no email", slug: "mentions-no-email")
    Membership.create!(workspace: workspace, user: author, role: :owner)
    Membership.create!(workspace: workspace, user: mentioned, role: :member)
    page = Page.create!(workspace: workspace, created_by: author, title: "Mentions Page no email")

    sign_in author

    expect do
      post page_comments_path(workspace_slug: workspace.slug, page_id: page.id),
           params: { comment: { body: "Please review this @mention-target-no-email@example.com" } }
    end.not_to change { ActionMailer::Base.deliveries.size }

    notification = Notification.where(recipient: mentioned).last
    expect(notification).to be_present
  end

  it "does not allow viewing another user's notifications" do
    actor = User.create!(email: "notif-actor-2@example.com", password: "password123")
    recipient = User.create!(email: "notif-recipient-2@example.com", password: "password123")
    outsider = User.create!(email: "notif-outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notif Access", slug: "notif-access")
    Membership.create!(workspace: workspace, user: recipient, role: :member)
    Membership.create!(workspace: workspace, user: outsider, role: :member)
    notification = Notification.create!(workspace: workspace, actor: actor, recipient: recipient, notification_type: "mention", metadata: {})

    sign_in outsider
    patch read_workspace_notification_path(workspace_slug: workspace.slug, id: notification.id)

    expect(response).to have_http_status(:not_found)
    expect(notification.reload.read_at).to be_nil
  end
end
