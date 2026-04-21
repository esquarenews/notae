require "rails_helper"

RSpec.describe "Mobile UX styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "coordinates bottom-fixed mobile UI so prompts, AI, toasts, and content do not overlap" do
    expect(stylesheet).to include("--notae-mobile-bottom-nav-offset: calc(env(safe-area-inset-bottom, 0px) + 0.72rem);")
    expect(stylesheet).to include("--notae-mobile-bottom-clearance: calc(var(--notae-mobile-bottom-nav-offset) + var(--notae-mobile-bottom-nav-height) + 0.85rem);")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-content {\n    padding: var(--notae-topbar-content-clearance) 0.8rem var(--notae-mobile-bottom-clearance);\n  }")
    expect(stylesheet).to include(".notae-shell.is-mobile-viewport .notae-ai-floating-toggle {\n    bottom: var(--notae-mobile-floating-bottom);")
    expect(stylesheet).to include(".notae-pwa-network-toast {\n    bottom: calc(var(--notae-mobile-bottom-clearance) + 4.35rem);")
  end

  it "makes the compact AI rail behave like a constrained mobile sheet" do
    expect(stylesheet).to include(".notae-shell.is-ai-compact-viewport.is-ai-rail-overlay-open .notae-ai-rail {\n  display: flex;\n  position: fixed;\n  inset: calc(env(safe-area-inset-top, 0px) + 0.35rem) 0 0 auto;")
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
end
