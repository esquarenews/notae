require "rails_helper"
require "open3"

RSpec.describe "NotificationBarController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/notification_bar_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "updates the shell clock with Intl date formatting" do
    source = Rails.root.join("app/javascript/controllers/notification_bar_controller.js").read

    expect(source).to include("renderClock()")
    expect(source).to include("Intl.DateTimeFormat")
    expect(source).to include("weekday: \"short\"")
    expect(source).to include("minute: \"2-digit\"")
    expect(source).to include("timeZone")
  end
end
