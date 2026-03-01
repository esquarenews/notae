require "rails_helper"
require "open3"

RSpec.describe "ActionsMenuController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/actions_menu_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps mobile drilldown hooks for actions panels" do
    source = Rails.root.join("app/javascript/controllers/actions_menu_controller.js").read

    expect(source).to include("is-mobile-drilldown")
    expect(source).to include("is-mobile-detail-open")
    expect(source).to include("showList")
    expect(source).to include("openSection")
  end
end
