require "rails_helper"
require "open3"

RSpec.describe "LazyPanelController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/lazy_panel_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps same-origin lazy loading with loading and error states" do
    source = Rails.root.join("app/javascript/controllers/lazy_panel_controller.js").read

    expect(source).to include("credentials: \"same-origin\"")
    expect(source).to include("\"X-Requested-With\": \"XMLHttpRequest\"")
    expect(source).to include("this.dispatch(\"loaded\")")
    expect(source).to include("this.dispatch(\"error\")")
    expect(source).to include("renderStatus(\"loading\")")
    expect(source).to include("renderStatus(\"error\")")
  end
end
