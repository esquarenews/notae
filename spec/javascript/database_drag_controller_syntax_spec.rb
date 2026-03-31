require "rails_helper"
require "open3"

RSpec.describe "DatabaseDragController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/database_drag_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "contains drag animation and board dialog hooks for board cards" do
    source = Rails.root.join("app/javascript/controllers/database_drag_controller.js").read

    expect(source).to include("dragenter")
    expect(source).to include("dragover")
    expect(source).to include("drop")
    expect(source).to include("beginEdit")
    expect(source).to include("openDialog")
    expect(source).to include("showModal")
    expect(source).to include("closeDialogOnBackdrop")
    expect(source).to include("refreshBoardOnSubmit")
    expect(source).to include("event.preventDefault()")
    expect(source).to include("closeReason === \"explicit\"")
    expect(source).to include("dialog.dataset.closeReason = reason")
    expect(source).to include("window.Turbo?.visit")
    expect(source).to include("currentTargetIndex")
    expect(source).to include("is-drop-target")
    expect(source).to include("is-drop-settling")
  end
end
