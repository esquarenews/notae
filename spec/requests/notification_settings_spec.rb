require "rails_helper"

RSpec.describe "Notification settings", type: :request do
  it "renders notifications settings with the readiness center and master push switch" do
    user = User.create!(email: "notification-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings", slug: "notification-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    user.web_push_subscriptions.create!(
      endpoint: "https://web.push.apple.com/QH123/subscriptions/test-device",
      p256dh: "p256dh-render",
      auth: "auth-render",
      last_error_at: 5.minutes.ago
    )
    user.web_push_delivery_attempts.create!(
      workspace: workspace,
      endpoint_host: "web.push.apple.com",
      notification_type: Notification::TYPE_TEST_PUSH,
      title: "Notae test notification",
      body: "Banner confirmed on device",
      status: :delivered,
      delivered_at: 1.minute.ago
    )
    sign_in user

    get workspace_notification_settings_path(workspace_slug: workspace.slug)
    document = Nokogiri::HTML.parse(response.body)
    mobile_settings_nav = document.at_css(".notae-settings-mobile-accordion")

    expect(response).to have_http_status(:ok)
    expect(mobile_settings_nav).to be_present
    expect(mobile_settings_nav["open"]).to be_nil
    expect(response.body).to include("In-app notifications")
    expect(response.body).to include("Push notifications on this device")
    expect(response.body).to include("AI suggestions")
    expect(response.body).to include("role=\"switch\"")
    expect(response.body).to include("data-action=\"pwa#togglePush\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsToggle\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsStateLabel\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsStatus\"")
    expect(response.body).to include("Send test push")
    expect(response.body).to include("data-pwa-target=\"pushSettingsFeedback\"")
    expect(response.body).to include("Notification readiness")
    expect(response.body).to include("Browser permission")
    expect(response.body).to include("Device subscription")
    expect(response.body).to include("Test push delivery")
    expect(response.body).to include("Banner seen on device")
    expect(response.body).to include("I saw the banner")
    expect(response.body).to include("No banner appeared")
    expect(response.body).to include("Collapse this once the device is fully configured.")
    expect(response.body).to include("Master push switch")
    expect(response.body).to include("data-pwa-target=\"pushSettingsReadinessBadge\"")
    expect(response.body).to include("data-pwa-target=\"pushReadinessPermissionPill\"")
    expect(response.body).to include("data-pwa-target=\"pushReadinessBannerPill\"")
    expect(response.body).to include("Push notification types")
    expect(response.body).to include("Mentions and comments")
    expect(response.body).to include("Workflow failures")
    expect(response.body).to include('data-controller="notification-preferences"')
    expect(response.body).to include('data-notification-preferences-target="masterToggle"')
    expect(response.body).to include('data-notification-preferences-target="itemToggle"')
    expect(response.body).to include("Quiet hours")
    expect(response.body).to include("notae-pref-row--quiet-hours-window")
    expect(response.body).to include("notae-pref-control-form--quiet-hours")
    expect(response.body).to include("notae-quiet-hours-field-label")
    expect(response.body).to include("Start")
    expect(response.body).to include("End")
    expect(response.body).to include("Current workspace overrides")
    expect(response.body).to include("Workspace activity emails")
    expect(response.body).to include("Workspace push overrides")
    expect(response.body).to include("Workspace push switch")
    expect(response.body).to include("Push delivery state")
    expect(response.body).to include("Recent push history")
    expect(response.body).to include("web.push.apple.com")
    expect(response.body).to include("Notae test notification")
    expect(response.body).to include("Banner confirmed on device")
    expect(response.body).to include("data-action=\"pwa#sendTestPush\"")
    expect(response.body).to include("data-pwa-target=\"pushSettingsTestButton\"")
    expect(response.body).to include(%(data-push-test-path="/w/#{workspace.slug}/settings/notifications/test-push"))
    expect(response.body).to include("Email notifications")
    expect(response.body).to include(%(href="/w/#{workspace.slug}/settings/preferences"))
    expect(response.body).to include("Preferences")
    expect(response.body).to include(%(href="/w/#{workspace.slug}/settings/notifications"))
    expect(response.body).to include("Notifications")
    expect(response.body).not_to include("Join video conferencing and start transcribing")
    expect(response.body).not_to include("Slack notifications")
    expect(response.body).not_to include("Discord notifications")
    expect(response.body).not_to include("Preferences <em>Future</em>")
    expect(response.body).not_to include("Notifications <em>Future</em>")
  end

  it "updates notification preference values for signed-in user" do
    user = User.create!(email: "notification-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings update", slug: "notification-settings-update")
    membership = Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notification_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              push_notify_mentions: "0",
              push_notify_workflow_failures: "1",
              push_quiet_hours_enabled: "1",
              push_quiet_hours_starts_at: "21:30",
              push_quiet_hours_ends_at: "06:45",
              email_notify_activity: "0",
              email_notify_always_send: "1",
              email_notify_page_updates: "0",
              email_notify_workspace_digest: "0"
            },
            membership: {
              email_notify_activity: "1",
              push_notify_mentions: "0",
              push_notify_workflow_failures: "1"
            }
          }

    expect(response).to redirect_to(workspace_notification_settings_path(workspace_slug: workspace.slug))

    user.reload
    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION)).to be(false)
    expect(user.push_notification_enabled_for?(Notification::TYPE_WORKFLOW_FAILED)).to be(true)
    expect(user.push_quiet_hours_enabled).to be(true)
    expect(user.push_quiet_hours_starts_at).to eq("21:30")
    expect(user.push_quiet_hours_ends_at).to eq("06:45")
    expect(user.email_notify_activity).to be(false)
    expect(user.email_notify_always_send).to be(true)
    expect(user.email_notify_page_updates).to be(false)
    expect(user.email_notify_workspace_digest).to be(false)

    expect(membership.reload.workspace_email_notify_activity_override).to be(true)
    expect(membership.workspace_push_notification_override(Notification::TYPE_MENTION)).to be_nil
    expect(membership.workspace_push_notification_override(Notification::TYPE_WORKFLOW_FAILED)).to be_nil
    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION, workspace: workspace, membership: membership)).to be(false)
  end

  it "persists individual push notification choices without the master toggle overwriting them" do
    user = User.create!(email: "notification-settings-master-switch@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification master switch", slug: "notification-master-switch")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    push_params = User::PUSH_NOTIFICATION_OPTIONS.each_with_object({}) do |option, params_hash|
      params_hash[option[:param_key]] = option[:type] == Notification::TYPE_WORKFLOW_FAILED ? "1" : "0"
    end

    patch workspace_notification_settings_path(workspace_slug: workspace.slug),
          params: { user: push_params }

    user.reload
    expect(user.push_notification_enabled_for?(Notification::TYPE_WORKFLOW_FAILED)).to be(true)
    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION)).to be(false)
    expect(user.push_notification_enabled_for?(Notification::TYPE_CALENDAR_REMINDER)).to be(false)
  end

  it "returns a local turbo stream flash instead of redirecting for auto-save updates" do
    user = User.create!(email: "notification-settings-turbo@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification turbo", slug: "notification-settings-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notification_settings_path(workspace_slug: workspace.slug),
          params: { user: { email_notify_activity: "0" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include("Notification settings updated.")
  end

  it "fans a test push out to all registered subscriptions and reports whether the current browser received it" do
    user = User.create!(email: "notification-settings-test-push@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings push", slug: "notification-settings-push")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    other_subscription = user.web_push_subscriptions.create!(
      endpoint: "https://push.example.test/subscriptions/other-device",
      p256dh: "p256dh-other",
      auth: "auth-other"
    )
    current_subscription = user.web_push_subscriptions.create!(
      endpoint: "https://push.example.test/subscriptions/test-device",
      p256dh: "p256dh-test",
      auth: "auth-test"
    )
    current_delivery_service = instance_double(WebPush::DeliveryService, call: true)
    other_delivery_service = instance_double(WebPush::DeliveryService, call: true)
    sign_in user

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::DeliveryService).to receive(:new) do |subscription:, **|
      case subscription.endpoint
      when current_subscription.endpoint
        current_delivery_service
      when other_subscription.endpoint
        other_delivery_service
      else
        raise "Unexpected subscription endpoint #{subscription.endpoint}"
      end
    end

    post workspace_notification_settings_test_push_path(workspace_slug: workspace.slug),
         params: { endpoint: current_subscription.endpoint },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include(
      "ok" => true,
      "message" => "Test push sent to 2 devices.",
      "current_device_delivered" => true,
      "delivered_subscription_count" => 2
    )
    notification = Notification.order(:created_at).last
    expect(notification.notification_type).to eq(Notification::TYPE_TEST_PUSH)
    expect(notification.recipient).to eq(user)
    expect(notification.metadata).to include(
      "title" => "Notae test notification",
      "path" => workspace_notification_settings_path(workspace_slug: workspace.slug),
      "endpoint" => current_subscription.endpoint
    )
    expect(WebPush::DeliveryService).to have_received(:new).with(
      subscription: current_subscription,
      notification: notification,
      payload: hash_including(
        title: "Notae test notification",
        url: "/app/notifications/#{notification.id}"
      )
    )
    expect(WebPush::DeliveryService).to have_received(:new).with(
      subscription: other_subscription,
      notification: notification,
      payload: hash_including(
        title: "Notae test notification",
        url: "/app/notifications/#{notification.id}"
      )
    )
  end

  it "returns a stale subscription error when the current device subscription expires during delivery" do
    user = User.create!(email: "notification-settings-test-push-stale@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification settings stale push", slug: "notification-settings-stale-push")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    subscription = user.web_push_subscriptions.create!(
      endpoint: "https://push.example.test/subscriptions/stale-device",
      p256dh: "p256dh-stale",
      auth: "auth-stale"
    )
    delivery_service = instance_double(WebPush::DeliveryService)
    sign_in user

    allow(WebPush::Configuration).to receive(:configured?).and_return(true)
    allow(WebPush::DeliveryService).to receive(:new).and_return(delivery_service)
    allow(delivery_service).to receive(:call) do
      subscription.destroy!
      false
    end

    post workspace_notification_settings_test_push_path(workspace_slug: workspace.slug),
         params: { endpoint: subscription.endpoint },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)).to include(
      "ok" => false,
      "error_code" => "stale_subscription"
    )
  end

  it "renders without raising when push delivery schema is unavailable" do
    user = User.create!(email: "notification-settings-schema-gap@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notification schema gap", slug: "notification-schema-gap")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    allow(ActiveRecord::Base.connection).to receive(:data_source_exists?).and_call_original
    allow(ActiveRecord::Base.connection).to receive(:data_source_exists?).with("web_push_subscriptions").and_return(false)
    allow(ActiveRecord::Base.connection).to receive(:data_source_exists?).with("web_push_delivery_attempts").and_return(false)

    allow(User).to receive(:column_names).and_call_original
    allow(User).to receive(:column_names).and_return(User.column_names - %w[
      push_notification_preferences
      push_quiet_hours_enabled
      push_quiet_hours_starts_at
      push_quiet_hours_ends_at
    ])

    allow(Membership).to receive(:column_names).and_call_original
    allow(Membership).to receive(:column_names).and_return(Membership.column_names - %w[notification_preferences_json])

    get workspace_notification_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Push delivery diagnostics are not available on this server yet.")
    expect(response.body).to include("Recent push history will appear here after the notification delivery schema is available.")
  end
end
