require "rails_helper"
require "open3"

RSpec.describe "DatabaseViewStateController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/database_view_state_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "stores and restores database view scroll state" do
    source = Rails.root.join("app/javascript/controllers/database_view_state_controller.js").read

    expect(source).to include("capture(event)")
    expect(source).to include("restoreAfterSubmit(event)")
    expect(source).to include("captureLink(event)")
    expect(source).to include("pendingSubmitState")
    expect(source).to include("currentStateFor(sourceElement = null)")
    expect(source).to include("restoreStoredPosition(scrollContainer, state)")
    expect(source).to include("restoreTrackedElementPosition(scrollContainer, state)")
    expect(source).to include("trackedViewportTop")
    expect(source).to include("selectorForTrackedElement(element)")
    expect(source).to include("restoreSubmitScrollPosition(state)")
    expect(source).to include("sessionStorage.setItem")
    expect(source).to include("restoreScrollPosition()")
    expect(source).to include("requestAnimationFrame")
    expect(source).to include("preserveScroll")
    expect(source).to include("scrollContainer()")
  end
end
