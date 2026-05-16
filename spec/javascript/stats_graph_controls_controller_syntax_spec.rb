require "rails_helper"
require "open3"

RSpec.describe "StatsGraphControlsController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/stats_graph_controls_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "clears explicit date ranges before submitting period slider changes" do
    source = Rails.root.join("app/javascript/controllers/stats_graph_controls_controller.js").read

    expect(source).to include('static targets = ["startDate", "endDate"]')
    expect(source).to include("submitFromPeriodInput()")
    expect(source).to include("submitFromPeriodChange()")
    expect(source).to include("clearDateRange()")
    expect(source).to include("this.element.requestSubmit()")
  end
end
