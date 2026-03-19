require "rails_helper"
require "open3"

RSpec.describe "BlockToolsController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_tools_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "anchors the block menu to the viewport so the nota scroller does not clip it" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("computeViewportPlacement")
    expect(source).to include("is-viewport-positioned")
    expect(source).to include("--notae-menu-left")
    expect(source).to include("--notae-menu-top")
    expect(source).to include("--notae-menu-max-height")
  end

  it "adds explicit dismissal handlers for viewport-anchored menus" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("document.addEventListener(\"pointerdown\", this.windowPointerDownHandler, true)")
    expect(source).to include("document.addEventListener(\"keydown\", this.documentKeydownHandler)")
    expect(source).to include("if (event.key !== \"Escape\") return")
    expect(source).to include("details.contains(target)")
    expect(source).to include("this.closeDetails(details)")
  end

  it "ignores scroll events that originate from the menu panel itself" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("panel.contains(scrollTarget)")
    expect(source).not_to include("panel.style.pointerEvents = \"none\"")
  end
end
