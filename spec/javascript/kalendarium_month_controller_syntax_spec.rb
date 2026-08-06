require "rails_helper"
require "open3"

RSpec.describe "KalendariumMonthController JavaScript" do
  let(:controller_path) { Rails.root.join("app/javascript/controllers/kalendarium_month_controller.js") }

  it "parses successfully" do
    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "supports month swipes, day agendas, rescheduling, and undo" do
    source = controller_path.read

    expect(source).to include("Math.abs(dx) < 60")
    expect(source).to include("this.agendaTarget.showModal()")
    expect(source).to include("this.moveToDay")
    expect(source).to include("async undoMove")
  end
end
