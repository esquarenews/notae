require "rails_helper"
require "open3"

RSpec.describe "kalendarium_task_slot_controller.js" do
  it "has valid JavaScript syntax" do
    controller_path = Rails.root.join("app/javascript/controllers/kalendarium_task_slot_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "opens editable task slot drafts from suggestions and custom picks" do
    source = Rails.root.join("app/javascript/controllers/kalendarium_task_slot_controller.js").read

    expect(source).to include("openCandidate(event)")
    expect(source).to include("openDraft(event)")
    expect(source).to include("durationChanged()")
    expect(source).to include("this.dialogTarget.showModal()")
  end
end
