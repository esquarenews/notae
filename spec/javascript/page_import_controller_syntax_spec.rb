require "rails_helper"
require "open3"

RSpec.describe "PageImportController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/page_import_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "opens the centered import dialog and captures the selected block target" do
    source = Rails.root.join("app/javascript/controllers/page_import_controller.js").read

    expect(source).to include("showModal()")
    expect(source).not_to include("closeMenu")
    expect(source).to include("prepareSubmit()")
    expect(source).to include("window.notaeAiInsertionPoint?.blockId")
    expect(source).to include("this.insertAfterInputTarget.value = this.resolveBlockId()")
    expect(source).to include("document.getElementById(`block_${blockId}`)")
  end
end
