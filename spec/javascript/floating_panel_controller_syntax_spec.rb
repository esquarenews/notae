require "rails_helper"
require "open3"

RSpec.describe "floating_panel_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/floating_panel_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "positions floating panels relative to the shell frame" do
    source = Rails.root.join("app/javascript/controllers/floating_panel_controller.js").read

    expect(source).to include("const frame = this.positioningFrame(panel)")
    expect(source).to include("positioningFrame(panel)")
    expect(source).to include("const offsetParent = panel?.offsetParent")
    expect(source).to include("offsetParent.getBoundingClientRect()")
    expect(source).to include("panel.style.top = `${clampedTop - frame.top}px`")
    expect(source).to include("panel.style.left = `${left - frame.left}px`")
  end
end
