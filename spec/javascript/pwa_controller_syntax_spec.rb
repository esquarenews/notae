require "rails_helper"
require "open3"

RSpec.describe "PwaController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/pwa_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "manages install prompts, offline state, push subscriptions, and private cache clearing" do
    source = Rails.root.join("app/javascript/controllers/pwa_controller.js").read

    expect(source).to include("beforeinstallprompt")
    expect(source).to include("window.navigator.onLine")
    expect(source).to include("CLEAR_PRIVATE_CACHES")
    expect(source).to include("notae-pwa-is-offline")
    expect(source).to include("matchMedia(\"(display-mode: standalone)\")")
    expect(source).to include("Notification.requestPermission")
    expect(source).to include("pushManager.subscribe")
    expect(source).to include("/pwa/push-subscription")
    expect(source).to include("togglePush(event)")
    expect(source).to include("sendTestPush(event)")
    expect(source).to include("disablePushNotifications")
    expect(source).to include("pushSettingsToggle")
    expect(source).to include("pushSettingsStateLabel")
    expect(source).to include("pushSettingsStatus")
    expect(source).to include("pushSettingsTestButton")
    expect(source).to include("pushSettingsFeedback")
    expect(source).to include("setPushSettingsFeedback(message, tone = \"neutral\")")
    expect(source).to include("Test push sent to this device.")
    expect(source).to include("Push notifications turned off on this device.")
    expect(source).to include("Home Screen app")
  end
end
