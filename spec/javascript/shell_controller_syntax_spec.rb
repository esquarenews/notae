require "rails_helper"
require "open3"

RSpec.describe "ShellController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/shell_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the visual viewport fallback hooks for mobile shell layout" do
    source = Rails.root.join("app/javascript/controllers/shell_controller.js").read

    expect(source).to include("visualViewport")
    expect(source).to include("is-mobile-viewport")
    expect(source).to include("viewportWidth()")
  end

  it "copies the current block markdown through the action menu export control" do
    source = Rails.root.join("app/javascript/controllers/shell_controller.js").read

    expect(source).to include("copyCurrentBlockMarkdown(event)")
    expect(source).to include("event.currentTarget?.dataset?.blockMarkdownUrlTemplate")
    expect(source).to include("window.notaeAiInsertionPoint?.blockId")
    expect(source).to include("new CustomEvent(\"notae:block-flush-save\"")
    expect(source).to include("fetch(url, {")
    expect(source).to include("headers: { Accept: \"text/markdown\" }")
  end
end
