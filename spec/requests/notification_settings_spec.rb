require "rails_helper"

RSpec.describe "Notification settings", type: :request do
  it "renders notifications settings and keeps completed menu items untagged" do
    user = User.create!(email: "notification-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings", slug: "notification-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_notification_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("In-app notifications")
    expect(response.body).to include("Push notifications on this device")
    expect(response.body).to include("AI suggestions")
    expect(response.body).to include("role=\"switch\"")
    expect(response.body).to include("data-action=\"pwa#togglePush\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsToggle\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsStateLabel\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsStatus\"")
    expect(response.body).to include("Slack notifications")
    expect(response.body).to include("Discord notifications")
    expect(response.body).to include("Email notifications")
    expect(response.body).to include(%(href="/w/#{workspace.slug}/settings/preferences"))
    expect(response.body).to include("Preferences")
    expect(response.body).to include(%(href="/w/#{workspace.slug}/settings/notifications"))
    expect(response.body).to include("Notifications")
    expect(response.body).not_to include("Preferences <em>Future</em>")
    expect(response.body).not_to include("Notifications <em>Future</em>")
  end

  it "updates notification preference values for signed-in user" do
    user = User.create!(email: "notification-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings update", slug: "notification-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notification_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              meeting_notify_join_transcribing: "1",
              meeting_notify_transcribed: "0",
              meeting_notify_summarized: "1",
              slack_notification_preference: "mentions",
              discord_notification_preference: "all_activity",
              email_notify_activity: "0",
              email_notify_always_send: "1",
              email_notify_page_updates: "0",
              email_notify_workspace_digest: "0"
            }
          }

    expect(response).to redirect_to(workspace_notification_settings_path(workspace_slug: workspace.slug))

    user.reload
    expect(user.meeting_notify_join_transcribing).to be(true)
    expect(user.meeting_notify_transcribed).to be(false)
    expect(user.meeting_notify_summarized).to be(true)
    expect(user.slack_notification_preference).to eq("mentions")
    expect(user.discord_notification_preference).to eq("all_activity")
    expect(user.email_notify_activity).to be(false)
    expect(user.email_notify_always_send).to be(true)
    expect(user.email_notify_page_updates).to be(false)
    expect(user.email_notify_workspace_digest).to be(false)
  end
end
