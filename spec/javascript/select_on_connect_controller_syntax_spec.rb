require "rails_helper"
require "open3"

RSpec.describe "SelectOnConnectController JavaScript syntax" do
  it "parses successfully and selects its connected input after Turbo finishes rendering" do
    controller_path = Rails.root.join("app/javascript/controllers/select_on_connect_controller.js")
    source = controller_path.read
    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), stdout
    expect(source).to include('static targets = ["input"]')
    expect(source).to include("window.setTimeout(() => this.focusAndSelect(), 0)")
    expect(source).to include("this.inputTarget.focus({ preventScroll: true })")
    expect(source).to include("this.inputTarget.select()")
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end
end
