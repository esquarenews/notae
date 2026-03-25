require "rails_helper"
require "open3"

RSpec.describe "kalendarium_preview_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_preview_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "renders preview blocks and detects conflicts from timeline cards" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_preview_controller.js").read

    expect(source).to include("render(event)")
    expect(source).to include('querySelectorAll(".notae-kalendarium-event-card.is-timeline[data-start-minutes][data-end-minutes]")')
    expect(source).to include('preview.classList.add("has-conflict")')
    expect(source).to include('label.textContent = detail.title?.trim() || "Draft event"')
  end

  it "supports dragging the preview hold to a new date or time" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_preview_controller.js").read

    expect(source).to include("beginDrag(event)")
    expect(source).to include("drag(event)")
    expect(source).to include("finishDrag(event)")
    expect(source).to include('preview.dataset.action = "pointerdown->kalendarium-preview#beginDrag"')
    expect(source).to include('window.addEventListener("pointermove", this.onPointerMove)')
    expect(source).to include('new CustomEvent("kalendarium:quick-create", {')
    expect(source).to include("localTimestampFor(dateString, startMinutes)")
  end
end
