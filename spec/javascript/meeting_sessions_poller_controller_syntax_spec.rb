require "rails_helper"
require "open3"

RSpec.describe "MeetingSessionsPollerController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/meeting_sessions_poller_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "polls using a lightweight json status endpoint" do
    source = Rails.root.join("app/javascript/controllers/meeting_sessions_poller_controller.js").read

    expect(source).to include("window.fetch")
    expect(source).to include("Accept: \"application/json\"")
    expect(source).to include("this.sectionsTarget.innerHTML")
    expect(source).to include("setInterval")
  end
end
