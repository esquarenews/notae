require "rails_helper"
require "open3"

RSpec.describe "KalendariumEventFormController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "enforces future minimum end time when configured" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js").read

    expect(source).to include("this.enforceFutureEndValue")
    expect(source).to include("this.endInputTarget.min = minimum")
    expect(source).to include("T23:59")
  end
end
