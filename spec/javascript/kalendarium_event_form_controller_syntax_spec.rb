require "rails_helper"
require "open3"

RSpec.describe "KalendariumEventFormController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "enforces future minimum end time when configured" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js").read

    expect(source).to include("this.enforceFutureEndValue")
    expect(source).to include("this.endInputTarget.min = minimum")
    expect(source).to include("T23:59")
  end

  it "publishes preview events for the create-event rail" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js").read

    expect(source).to include("previewEnabled")
    expect(source).to include("publishPreview()")
    expect(source).to include('this.dispatchPreview("kalendarium:preview-event", detail)')
    expect(source).to include('this.dispatchPreview("kalendarium:preview-clear", {})')
    expect(source).to include('shell.dispatchEvent(new CustomEvent(name, {')
  end

  it "supports canceling the draft event hold" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js").read

    expect(source).to include("cancel(event)")
    expect(source).to include("this.element.reset()")
    expect(source).to include('this.startInputTarget.value = `${selectedDate}T09:00`')
    expect(source).to include('this.endInputTarget.value = `${selectedDate}T10:00`')
    expect(source).to include("this.accordionElement.open = false")
    expect(source).to include("this.dialogElement = this.element.closest(\"dialog\")")
    expect(source).to include("this.dialogElement?.open")
    expect(source).to include("this.dialogElement.close()")
  end

  it "supports recurrence controls and calendar event copy paste" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_event_form_controller.js").read

    expect(source).to include("frequencyChanged()")
    expect(source).to include("customRecurrenceChanged()")
    expect(source).to include("copyEvent(event)")
    expect(source).to include("pasteEvent(event)")
    expect(source).to include("notae:kalendarium:event-copy")
    expect(source).to include("FREQ=DAILY")
    expect(source).to include("FREQ=WEEKLY;BYDAY=")
    expect(source).to include("customRruleValue()")
    expect(source).to include("localDateTimeObject(value)")
    expect(source).to include("Number.parseInt(month, 10) - 1")
  end
end
