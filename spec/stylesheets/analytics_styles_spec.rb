require "rails_helper"

RSpec.describe "Personal analytics styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "keeps the dashboard responsive and respects reduced motion" do
    expect(stylesheet).to include(".notae-analytics-content")
    expect(stylesheet).to include(".notae-analytics-trend")
    expect(stylesheet).to include(".notae-analytics-split")
    expect(stylesheet).to include("@media (max-width: 760px)")
    expect(stylesheet).to include("@media (prefers-reduced-motion: reduce)")
    guard_index = stylesheet.rindex(".notae-settings-content.notae-analytics-content")
    shared_index = stylesheet.rindex(/^\.notae-settings-content \{/)
    expect(guard_index).to be > shared_index
    expect(stylesheet).to include("--notae-text-soft: var(--notae-text-muted)")
    expect(stylesheet).to include(".notae-analytics-bars li > div > span:first-child")
    expect(stylesheet).to include("overflow-wrap: anywhere")
    expect(stylesheet).to include("--notae-analytics-teal")
    expect(stylesheet).to include("--notae-analytics-amber")
    expect(stylesheet).to include("--notae-analytics-violet")
    expect(stylesheet).to include(".notae-analytics-trend-change.is-up")
    expect(stylesheet).to include(".notae-analytics-trend-change.is-down")
    expect(stylesheet).to include("background: color-mix(in srgb, var(--notae-analytics-series) 3.5%, transparent)")
  end
end
