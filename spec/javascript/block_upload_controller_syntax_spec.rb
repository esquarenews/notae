require "rails_helper"
require "open3"

RSpec.describe "BlockUploadController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_upload_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "replaces the uploaded media block in place instead of reloading the page" do
    source = Rails.root.join("app/javascript/controllers/block_upload_controller.js").read

    expect(source).to include("Accept\": \"application/json\"")
    expect(source).to include("const payload = await response.json()")
    expect(source).to include("this.element.outerHTML = payload.html")
    expect(source).not_to include("window.location.reload()")
  end
end
