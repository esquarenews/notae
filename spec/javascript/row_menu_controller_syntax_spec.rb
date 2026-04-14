require "rails_helper"
require "open3"

RSpec.describe "RowMenuController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/row_menu_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps floating row menus inside open dialogs when needed" do
    source = Rails.root.join("app/javascript/controllers/row_menu_controller.js").read

    expect(source).to include(".notae-db-row-hover-controls, .notae-db-column-hover-controls")
    expect(source).to include("closest(\"dialog[open]\") || document.body")
    expect(source).to include("this.portalRoot = nextPortalRoot")
    expect(source).to include("this.portalRoot = null")
  end
end
