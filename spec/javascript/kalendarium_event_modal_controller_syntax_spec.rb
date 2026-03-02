require "rails_helper"
require "open3"

RSpec.describe "KalendariumEventModalController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_event_modal_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "ignores openView key events while the dialog is already open" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_modal_controller.js").read

    expect(source).to include("event.type === \"keydown\" && this.hasDialogTarget && this.dialogTarget.open")
    expect(source).to include("if (this.interactiveTarget(event.target)) return")
  end
end
