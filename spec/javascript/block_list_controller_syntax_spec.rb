require "rails_helper"
require "open3"

RSpec.describe "BlockListController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_list_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "uses a custom drag mime type for block reordering" do
    source = Rails.root.join("app/javascript/controllers/block_list_controller.js").read

    expect(source).to include('application/x-notae-block-id')
    expect(source).not_to include('setData("text/plain"')
    expect(source).to include('getData(BLOCK_DRAG_MIME)')
  end

  it "flushes pending block saves and waits until drop before moving the DOM" do
    source = Rails.root.join("app/javascript/controllers/block_list_controller.js").read

    expect(source).to include("prepareDragStart(event)")
    expect(source).to include('window.dispatchEvent(new CustomEvent("notae:block-flush-save"')
    expect(source).to include("await this.flushDraggedBlockSave()")
    expect(source).to include("resolveDropPlacement(event, draggedId)")
    expect(source).to include("applyDropPlacement(placement)")
  end
end
