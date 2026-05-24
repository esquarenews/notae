require "rails_helper"
require "open3"

RSpec.describe "TimesheetTimerController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/timesheet_timer_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "renders elapsed time every second from the started timestamp" do
    source = Rails.root.join("app/javascript/controllers/timesheet_timer_controller.js").read

    expect(source).to include("static targets = [\"elapsed\"]")
    expect(source).to include("static values = { startedAt: String }")
    expect(source).to include("window.setInterval(() => this.render(), 1000)")
    expect(source).to include("formatElapsed(milliseconds)")
    expect(source).to include("pad(hours)")
    expect(source).to include("pad(minutes)")
    expect(source).to include("pad(seconds)")
  end
end
