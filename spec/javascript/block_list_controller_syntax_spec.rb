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

  it "uses pointer capture for reliable block reordering" do
    source = Rails.root.join("app/javascript/controllers/block_list_controller.js").read

    expect(source).to include("event.currentTarget.setPointerCapture(event.pointerId)")
    expect(source).to include("handlePointerMove(event)")
    expect(source).to include("document.elementFromPoint(clientX, clientY)")
    expect(source).to include("POINTER_DRAG_THRESHOLD_PX")
  end

  it "flushes pending block saves and waits until drop before moving the DOM" do
    source = Rails.root.join("app/javascript/controllers/block_list_controller.js").read

    expect(source).to include("prepareDragStart(event)")
    expect(source).to include('window.dispatchEvent(new CustomEvent("notae:block-flush-save"')
    expect(source).to include("await this.flushDraggedBlockSave()")
    expect(source).to include("resolveDropPlacement(event, draggedId)")
    expect(source).to include("applyDropPlacement(placement)")
  end

  it "limits pointer drop targets to direct siblings in the active block tree" do
    source = Rails.root.join("app/javascript/controllers/block_list_controller.js").read

    expect(source).to include("directSiblingItemAtPoint(clientX, clientY)")
    expect(source).to include("candidate.parentElement !== this.element")
  end
end
