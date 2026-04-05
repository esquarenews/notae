require "rails_helper"
require "open3"

RSpec.describe "AiRailLoaderController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/ai_rail_loader_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "defers the rail request until open or AI prefill is requested" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_loader_controller.js").read

    expect(source).to include('window.addEventListener("notae:ai-prefill"')
    expect(source).to include("window.notaeAiRailPendingPrefill = detail")
    expect(source).to include('window.notaeAiRailPendingOpen = mode')
    expect(source).to include('this.element.setAttribute("src", this.srcValue)')
  end
end
