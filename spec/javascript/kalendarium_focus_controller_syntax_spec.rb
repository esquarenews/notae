require "rails_helper"
require "open3"

RSpec.describe "kalendarium_focus_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_focus_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "wires quick-create events into the create form targets" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_focus_controller.js").read

    expect(source).to include("prepareNewEvent(event)")
    expect(source).to include("createAccordion")
    expect(source).to include("createDialog")
    expect(source).to include("createStartInput")
    expect(source).to include("createEndInput")
    expect(source).to include("createTitleInput")
    expect(source).to include("dispatchChange(this.createStartInputTarget)")
    expect(source).to include("dispatchChange(this.createEndInputTarget)")
    expect(source).to include("openCreateModal(event)")
    expect(source).to include("quickCreateDay(event)")
    expect(source).to include("dayFocusTarget(target)")
    expect(source).to include("minimizeWidget(event)")
    expect(source).to include("window.parent.postMessage")
  end

  it "formats the rolling next-7-days label from the window start value" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_focus_controller.js").read

    expect(source).to include("windowStart: String")
    expect(source).to include("view === \"next_7_days\"")
    expect(source).to include("endDate.setUTCDate(endDate.getUTCDate() + 6)")
    expect(source).to include("return `${startLabel} - ${endLabel}`")
  end
end
