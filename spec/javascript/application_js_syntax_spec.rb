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

  it "lazy loads Stimulus controllers instead of blocking every page on editor dependencies" do
    source = Rails.root.join("app/javascript/controllers/index.js").read
    importmap = Rails.root.join("config/importmap.rb").read

    expect(source).to include('import WhiteboardController from "controllers/whiteboard_controller"')
    expect(source).to include('application.register("whiteboard", WhiteboardController)')
    expect(source).to include("lazyLoadControllersFrom")
    expect(source).to include('lazyLoadControllersFrom("controllers", application)')
    expect(source).not_to include("eagerLoadControllersFrom")
    expect(importmap).to include('pin_all_from "app/javascript/controllers", under: "controllers", preload: false')
    %w[
      @tiptap/core
      @tiptap/starter-kit
      @tiptap/extension-link
      @tiptap/extension-task-list
      @tiptap/extension-task-item
      three
    ].each do |package_name|
      expect(importmap).to match(/pin "#{Regexp.escape(package_name)}".*preload: false/)
    end
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
    expect(source).to include("function preserveScrollRequested(element)")
    expect(source).to include("preserveDatabaseScroll")
    expect(source).to include("window.sessionStorage.setItem(PRESERVED_SAVE_SCROLL_KEY")
    expect(source).to include("trackedViewportTop")
    expect(source).to include("document.addEventListener(\"submit\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:submit-start\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:submit-end\", (event) => {")
    expect(source).to include("document.addEventListener(\"turbo:render\", () => {")
    expect(source).to include("shouldDeferPreservedSaveScrollRestore(event)")
    expect(source).to include("response.redirected")
    expect(source).to include("restoreStoredSaveScroll()")
    expect(source).not_to include('if (!contentType.includes("turbo-stream")) return')
  end

  it "prefers explicit preserve keys and skips duplicate ids when tracking restore targets" do
    source = Rails.root.join("app/javascript/application.js").read

    expect(source).to include("sourceElement.closest(\"[data-scroll-preserve-key]\")")
    expect(source).to include("function uniqueIdSelectorFor(element)")
    expect(source).to include("document.querySelectorAll(selector).length !== 1")
  end

  it "keeps a preserved ai rail in sync with turbo page changes without replacing the rail" do
    source = Rails.root.join("app/javascript/application.js").read

    expect(source).to include("function syncPreservedAiRailContext(root = document)")
    expect(source).to include('input[name="ai_assistant[current_page_id]"]')
    expect(source).to include("dataset.aiRailCurrentPageIdValue")
    expect(source).to include("dataset.aiRailPanelSrcValue")
    expect(source).to include('turbo-frame#ai_rail_panel[data-controller~="ai-rail-loader"]')
    expect(source).to include('loaderFrame.querySelector(".notae-ai-rail-shell")')
    expect(source).to include("loaderFrame.hasAttribute(\"src\")")
    expect(source).to include("syncPreservedAiRailContext(document)")
    expect(source).to include("syncPreservedAiRailContext(newBody)")
  end
end
