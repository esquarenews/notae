require "rails_helper"
require "open3"

RSpec.describe "kalendarium_timeline_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_timeline_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "dispatches quick-create details from timeline double clicks" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_timeline_controller.js").read

    expect(source).to include("quickCreate(event)")
    expect(source).to include('new CustomEvent("kalendarium:quick-create"')
    expect(source).to include('new CustomEvent("kalendarium:task-slot-draft"')
    expect(source).to include("startLocal: this.localTimestampFor(dateString, startMinutes)")
    expect(source).to include("endLocal: this.localTimestampFor(dateString, endMinutes)")
    expect(source).to include("taskScheduling: Boolean")
  end

  it "can focus the initial scroll position on suggested task slots" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_timeline_controller.js").read

    expect(source).to include("initialFocusMinutes: Number")
    expect(source).to include("centerCurrentTime: Boolean")
    expect(source).to include("this.hasInitialFocusMinutesValue")
    expect(source).to include("this.initialFocusMinutesValue / 30.0")
    expect(source).to include("focusedScrollTop(")
  end
end
