require "rails_helper"
require "open3"

RSpec.describe "gantt_chart_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/gantt_chart_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "supports drag resizing and row-level color updates" do
    source = Rails.root.join("app/javascript/controllers/gantt_chart_controller.js").read

    expect(source).to include("startResize(event)")
    expect(source).to include("startMove(event)")
    expect(source).to include("updateRowColor(event)")
    expect(source).to include("set_gantt_color")
    expect(source).to include("onPointerMove(event)")
    expect(source).to include("onPointerUp()")
  end
end
