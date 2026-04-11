require "rails_helper"
require "open3"

RSpec.describe "Application JavaScript syntax" do
  it "parses successfully" do
    application_path = Rails.root.join("app/javascript/application.js")

    stdout, status = Open3.capture2e("node", "--check", application_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{application_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "recovers ai rail frame-missing responses instead of showing Turbo's placeholder" do
    source = Rails.root.join("app/javascript/application.js").read

    expect(source).to include('turbo:frame-missing')
    expect(source).to include('frame.id !== "ai_rail_panel"')
    expect(source).to include("window.Turbo.renderStreamMessage")
    expect(source).to include("await visit(response)")
  end

  it "registers the service worker only in supported secure contexts" do
    source = Rails.root.join("app/javascript/application.js").read

    expect(source).to include("navigator.serviceWorker.register(\"/service-worker.js\"")
    expect(source).to include("window.isSecureContext")
    expect(source).to include("[\"localhost\", \"127.0.0.1\", \"[::1]\"]")
    expect(source).to include("document.addEventListener(\"turbo:load\"")
  end

  it "preserves the current scroll position across save submits and turbo renders" do
    source = Rails.root.join("app/javascript/application.js").read

    expect(source).to include('const PRESERVED_SAVE_SCROLL_KEY = "notae-preserved-save-scroll"')
    expect(source).to include("function primaryScrollContainer()")
    expect(source).to include("document.querySelector(\".notae-content-scroll\")")
    expect(source).to include("window.sessionStorage.setItem(PRESERVED_SAVE_SCROLL_KEY")
    expect(source).to include("trackedViewportTop")
    expect(source).to include("document.addEventListener(\"submit\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:submit-start\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:submit-end\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:render\", () => {")
    expect(source).to include("restoreStoredSaveScroll()")
    expect(source).not_to include('if (!contentType.includes("turbo-stream")) return')
  end
end
