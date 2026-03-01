require "rails_helper"
require "open3"

RSpec.describe "AiRailController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/ai_rail_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the visual viewport fallback hooks for compact AI rail mode" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("visualViewport")
    expect(source).to include("is-ai-compact-viewport")
    expect(source).to include("viewportWidth()")
  end
end
