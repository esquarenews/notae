require "rails_helper"
require "open3"

RSpec.describe "MeetingCaptureController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/meeting_capture_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "includes explicit microphone permission recovery guidance" do
    source = Rails.root.join("app/javascript/controllers/meeting_capture_controller.js").read

    expect(source).to include("permission denied")
    expect(source).to include("lock/camera icon")
    expect(source).to include("window.isSecureContext")
    expect(source).to include("navigator.mediaDevices.getUserMedia")
    expect(source).to include("Permissions-Policy")
    expect(source).to include("microphoneFeatureAllowed")
    expect(source).to include("sessionTitleInput")
    expect(source).to include("syncSessionTitle")
    expect(source).to include("Recording in progress:")
  end
end
