require "rails_helper"
require "open3"

RSpec.describe "BlockToolsController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/block_tools_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "anchors the block menu to the viewport so the nota scroller does not clip it" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("computeViewportPlacement")
    expect(source).to include("visibleViewportBounds")
    expect(source).to include("is-viewport-positioned")
    expect(source).to include("--notae-menu-left")
    expect(source).to include("--notae-menu-top")
    expect(source).to include("--notae-menu-max-height")
  end

  it "keeps viewport menus below the visible nota content top in standalone PWA layouts" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("window.visualViewport")
    expect(source).to include("querySelector(\".notae-content-scroll\")")
    expect(source).to include("const safeTop = Number.isFinite(shellScrollTop) ? Math.max(viewportTop, shellScrollTop) : viewportTop")
    expect(source).to include("top: safeTop + MENU_VIEWPORT_MARGIN")
  end

  it "prefers opening tall block menus below the trigger instead of pinning them to the top" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("MENU_MIN_BELOW_SPACE")
    expect(source).to include("const belowTop = triggerRect.bottom + MENU_TRIGGER_GAP")
    expect(source).to include("const spaceBelow = Math.max(0, bounds.bottom - Math.max(bounds.top, belowTop))")
    expect(source).to include("const placeAbove = spaceBelow < MENU_MIN_BELOW_SPACE && spaceAbove > spaceBelow")
    expect(source).to include("let top = placeAbove ? aboveBottom - panelHeight : belowTop")
  end

  it "adds explicit dismissal handlers for viewport-anchored menus only when a menu opens" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("document.addEventListener(\"pointerdown\", this.windowPointerDownHandler, true)")
    expect(source).to include("document.addEventListener(\"keydown\", this.documentKeydownHandler)")
    expect(source).to include("installViewportHandlers()")
    expect(source).to include("removeViewportHandlers")
    expect(source).not_to include("window.addEventListener(\"notae:block-reparent\"")
    expect(source).to include("if (event.key !== \"Escape\") return")
    expect(source).to include("panel.contains(target)")
    expect(source).to include("trigger.contains(target)")
    expect(source).to include("this.closeDetails(details)")
  end

  it "ignores scroll events that originate from the menu panel itself" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("panel.contains(scrollTarget)")
    expect(source).not_to include("panel.style.pointerEvents = \"none\"")
  end

  it "raises the owning block row while the menu is open so it clears the page title" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(source).to include("this.setMenuOpenState(details, true)")
    expect(source).to include("this.setMenuOpenState(details, false)")
    expect(source).to include("closest(\".notae-doc-block-row\")")
    expect(source).to include("classList.toggle(\"is-menu-open\", isOpen)")
    expect(stylesheet).to include(".notae-doc-block-row.is-menu-open")
    expect(stylesheet).to include("z-index: 220;")
  end

  it "supports indent and outdent reparent actions" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("indent(event)")
    expect(source).to include("outdent(event)")
    expect(source).to include("handleReparentRequest(event)")
    expect(source).to include("persistReparent(plan)")
    expect(source).to include("flushBlockSave()")
    expect(source).to include("notae:block-flush-save")
    expect(source).to include("childTreeForBlock(block)")
    expect(source).to include("parentTreeForBlock(block)")
  end

  it "opens existing-link pickers from block menu buttons and submits on selection" do
    source = Rails.root.join("app/javascript/controllers/block_tools_controller.js").read

    expect(source).to include("togglePicker(event)")
    expect(source).to include("closest(\".notae-block-menu-picker-form\")")
    expect(source).to include("closest(\".notae-block-menu-picker-row\")")
    expect(source).to include("closeInlinePickers(form)")
    expect(source).to include("[data-document-picker-target='searchInput']")
    expect(source).to include("focusTarget.focus()")
  end
end
