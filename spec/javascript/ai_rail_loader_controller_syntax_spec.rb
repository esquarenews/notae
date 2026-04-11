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

  it "autoloads the desktop rail when expanded and still supports deferred opening" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_loader_controller.js").read

    expect(source).to include('const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"')
    expect(source).to include("const AI_RAIL_COMPACT_MAX_WIDTH = 1180")
    expect(source).to include("if (this.shouldAutoload()) this.load(this.defaultLoadMode())")
    expect(source).to include('window.addEventListener("notae:ai-prefill"')
    expect(source).to include("window.notaeAiRailPendingPrefill = detail")
    expect(source).to include('window.notaeAiRailPendingOpen = mode')
    expect(source).to include('return !this.railCollapsedPreference()')
    expect(source).to include("return window.innerWidth <= AI_RAIL_COMPACT_MAX_WIDTH")
    expect(source).to include('this.element.setAttribute("src", this.srcValue)')
  end
end
