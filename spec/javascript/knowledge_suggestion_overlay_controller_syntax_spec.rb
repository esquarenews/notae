require "rails_helper"
require "open3"

RSpec.describe "KnowledgeSuggestionOverlayController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/knowledge_suggestion_overlay_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "contains the overlay collapse lifecycle hooks" do
    source = Rails.root.join("app/javascript/controllers/knowledge_suggestion_overlay_controller.js").read

    expect(source).to include("collapse")
    expect(source).to include("expand")
    expect(source).to include("pause")
    expect(source).to include("resume")
    expect(source).to include("startTimer")
    expect(source).to include("clearTimer")
  end
end
