require "rails_helper"
require "open3"

RSpec.describe "ProgressCellController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/progress_cell_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "stores completion state and clears confetti after celebration" do
    source = Rails.root.join("app/javascript/controllers/progress_cell_controller.js").read

    expect(source).to include("window.sessionStorage?.setItem(this.storageKey(), \"1\")")
    expect(source).to include("this.valueValue < 10")
    expect(source).to include("this.launchConfetti()")
    expect(source).to include("window.setTimeout(() => this.clearCelebration(), 1400)")
  end
end
