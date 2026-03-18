require "rails_helper"
require "open3"

RSpec.describe "PageTitleController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/page_title_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "autosizes textarea-based page titles to avoid descender clipping" do
    source = Rails.root.join("app/javascript/controllers/page_title_controller.js").read

    expect(source).to include("resizeInput()")
    expect(source).to include("HTMLTextAreaElement")
    expect(source).to include("this.inputTarget.scrollHeight")
  end
end
