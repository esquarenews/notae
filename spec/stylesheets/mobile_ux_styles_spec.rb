require "rails_helper"

RSpec.describe "Mobile UX styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "coordinates bottom-fixed mobile UI so prompts, AI, toasts, and content do not overlap" do
    expect(stylesheet).to include("--notae-mobile-bottom-nav-offset: calc(env(safe-area-inset-bottom, 0px) + 0.72rem);")
    expect(stylesheet).to include("--notae-mobile-bottom-clearance: calc(var(--notae-mobile-bottom-nav-offset) + var(--notae-mobile-bottom-nav-height) + 0.85rem);")
    expect(stylesheet).to include("--notae-layer-mobile-tabbar: 65;")
    expect(stylesheet).to include("--notae-layer-pwa-shell: 360;")
    expect(stylesheet).to include("--notae-layer-pwa-banner: 380;")
    expect(stylesheet).to include("z-index: var(--notae-layer-mobile-tabbar);")
    expect(stylesheet).to include(".notae-pwa-shell {\n  position: relative;\n  z-index: var(--notae-layer-pwa-shell);\n}")
    expect(stylesheet).to include("z-index: var(--notae-layer-pwa-banner);")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-content {\n    padding: var(--notae-topbar-content-clearance) 0.8rem var(--notae-mobile-bottom-clearance);\n  }")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-ai-floating-toggle {\n    bottom: var(--notae-mobile-floating-bottom);")
    expect(stylesheet).to include(".notae-pwa-network-toast {\n    bottom: calc(var(--notae-mobile-bottom-clearance) + 4.35rem);")
  end

  it "makes the compact AI rail behave like a constrained mobile sheet" do
    expect(stylesheet).to include("--notae-layer-ai-overlay: 68;")
    expect(stylesheet).to include("--notae-layer-ai-rail: 70;")
    expect(stylesheet).to include("--notae-layer-ai-toast: 73;")
    expect(stylesheet).to include(".notae-ai-rail-overlay {\n  display: none;\n  position: fixed;\n  inset: 0;\n  border: 0;\n  background: rgba(28, 25, 23, 0.25);\n  z-index: var(--notae-layer-ai-overlay);\n}")
    expect(stylesheet).to include("z-index: var(--notae-layer-ai-toast);")
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport.is-ai-rail-overlay-open .notae-ai-rail {\n  display: flex;\n  position: fixed;\n  inset: calc(env(safe-area-inset-top, 0px) + 0.35rem) 0 0 auto;")
    expect(stylesheet).to include("z-index: var(--notae-layer-ai-rail);")
    expect(stylesheet).to include("  border-radius: 1.15rem 0 0 0;\n  border-left: 1px solid color-mix(in srgb, var(--notae-border) 82%, transparent);\n  overflow-x: hidden;")
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport.is-ai-rail-overlay-open .notae-ai-rail::before {\n  content: \"\";")
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport .notae-ai-head {\n  position: relative;\n  display: grid;\n  grid-template-columns: minmax(0, 1fr) auto;")
  end

  it "keeps mobile AI scope and usage controls compact without removing them" do
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport .notae-ai-scope-select {\n  min-height: 2.05rem;\n  max-width: 7.2rem;")
    expect(stylesheet).to include("  appearance: none;\n  background:")
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport .notae-ai-usage-toggle::after {\n  content: \"Details\";")
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport .notae-ai-usage-card {\n  max-height: 38dvh;\n  overflow-x: hidden;\n  overflow-y: auto;\n}")
  end

  it "applies shared mobile tap targets and active-state orientation cues" do
    expect(stylesheet).to include(".notae-mobile-tabbar-link.active::after {\n    content: \"\";")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-actions-trigger,")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-create-menu-button,")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-sidebar-link.active {\n  border-color: color-mix(in srgb, var(--notae-accent) 22%, var(--notae-border));")
  end

  it "guards mobile popovers against horizontal overflow" do
    expect(stylesheet).to include(".notae-actions-panel {\n  position: absolute;")
    expect(stylesheet).to include("  overflow-x: hidden;\n  overflow-y: auto;\n  overscroll-behavior: contain;")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-comments-panel *,\n.notae-shell.is-mobile-viewport .notae-options-panel *,\n.notae-shell.is-mobile-viewport .notae-actions-panel *,")
    expect(stylesheet).to include("  overscroll-behavior: contain;\n  touch-action: pan-y;\n  top: var(--notae-overlay-panel-top);")
  end

  it "prevents horizontal panning in the open mobile sidebar" do
    expect(stylesheet).to include("--notae-layer-mobile-sidebar-overlay: 80;")
    expect(stylesheet).to include("--notae-layer-mobile-sidebar: 90;")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport {\n  grid-template-columns: minmax(0, 1fr);\n  max-width: 100vw;\n  overflow-x: hidden;")
    expect(stylesheet).to include("z-index: var(--notae-layer-mobile-sidebar);")
    expect(stylesheet).to include("z-index: var(--notae-layer-mobile-sidebar-overlay);")
    expect(stylesheet).to include("body.notae-sidebar-open {\n  max-width: 100vw;\n  overflow: hidden;\n  overscroll-behavior: none;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-sidebar,\n.notae-shell.is-mobile-viewport .notae-sidebar * {\n  box-sizing: border-box;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-sidebar-scroll {\n  overscroll-behavior: contain;\n  touch-action: pan-y;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-sidebar-list.is-indented {\n  width: 100%;\n  padding-left: 0.45rem;\n}")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-sidebar-page-title {\n  display: block;\n}")
  end

  it "fits the complete month week across mobile with title-only event rows" do
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-month-grid {\n    grid-template-columns: repeat(7, minmax(0, 1fr));")
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-month-cell {\n    min-width: 0;\n    min-height: clamp(6rem, 26vw, 7rem);")
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-month-events > .notae-kalendarium-event-card:nth-child(n + 4) {\n    display: none;\n  }")
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-month-overflow-label {\n    display: inline-block;")
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-event-header-compact strong {\n    display: block;")
    expect(stylesheet).to include("    text-overflow: ellipsis;\n    white-space: nowrap;")
    expect(stylesheet).to include(".notae-kalendarium.is-month-view .notae-kalendarium-event-time-line,\n  .notae-kalendarium.is-month-view .notae-kalendarium-event-links {\n    display: none;")
  end
end
