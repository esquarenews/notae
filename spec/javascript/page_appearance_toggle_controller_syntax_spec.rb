require "rails_helper"
require "open3"

RSpec.describe "PageAppearanceToggleController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/page_appearance_toggle_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "uses the fast JSON page update path instead of relying on a redirect" do
    source = Rails.root.join("app/javascript/controllers/page_appearance_toggle_controller.js").read

    expect(source).to include('"Accept": "application/json"')
    expect(source).to include("notae-doc-layout")
    expect(source).to include("is-full-width")
    expect(source).to include("is-small-text")
    expect(source).to include("is-reader-mode")
  end
end
