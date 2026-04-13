require "rails_helper"
require "open3"

RSpec.describe "copy_text_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/copy_text_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "supports html clipboard payloads when available" do
    source = Rails.root.join("app/javascript/controllers/copy_text_controller.js").read

    expect(source).to include("copyTextHtmlValue")
    expect(source).to include("ClipboardItem")
    expect(source).to include("navigator.clipboard.write")
  end
end
