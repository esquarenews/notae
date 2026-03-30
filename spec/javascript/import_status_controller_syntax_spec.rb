require "rails_helper"
require "open3"

RSpec.describe "ImportStatusController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/import_status_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "shows progress and failure states for imports" do
    source = Rails.root.join("app/javascript/controllers/import_status_controller.js").read

    expect(source).to include("submitStart()")
    expect(source).to include("submitEnd(event)")
    expect(source).to include("Import in progress")
    expect(source).to include("Import failed")
    expect(source).to include("Importing...")
  end
end
