require "rails_helper"
require "open3"

RSpec.describe "BlockEditorController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_editor_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "guards the editor against block reorder drag payloads" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("handleDOMEvents")
    expect(source).to include("handleBlockReorderDragOver")
    expect(source).to include("handleBlockReorderDrop")
    expect(source).to include("application/x-notae-block-id")
  end

  it "dispatches tab-based block reparent requests" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include('event.key === "Tab"')
    expect(source).to include("notae:block-reparent")
    expect(source).to include('direction: event.shiftKey ? "outdent" : "indent"')
    expect(source).to include("focusEditor: true")
  end

  it "flushes pending editor saves before a block reparent happens" do
    source = Rails.root.join("app/javascript/controllers/block_editor_controller.js").read

    expect(source).to include("notae:block-flush-save")
    expect(source).to include("handleFlushSaveRequest(event)")
    expect(source).to include("event.detail.promise = this.flushSave()")
    expect(source).to include("flushSave()")
    expect(source).to include("if (!this.hasPendingChanges) return true")
  end
end
