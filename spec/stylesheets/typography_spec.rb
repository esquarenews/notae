require "rails_helper"

RSpec.describe "Notae typography" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }
  let(:layout) { Rails.root.join("app/views/layouts/application.html.erb").read }

  it "loads the upright and true italic variable families across the full weight axis" do
    expect(stylesheet.scan(/@font-face/).length).to be >= 2
    expect(stylesheet).to include(<<~CSS)
      @font-face {
        font-family: "Notae Sans";
        src: url("notae_sans/notae-sans-variable.woff2") format("woff2");
        font-style: normal;
        font-weight: 100 900;
        font-display: swap;
      }
    CSS
    expect(stylesheet).to include(<<~CSS)
      @font-face {
        font-family: "Notae Sans";
        src: url("notae_sans/notae-sans-italic-variable.woff2") format("woff2");
        font-style: italic;
        font-weight: 100 900;
        font-display: swap;
      }
    CSS
    expect(stylesheet).to include('font-family: "Notae Sans", "Avenir Next", "Segoe UI", sans-serif;')
    expect(stylesheet).to include("font-synthesis: none;")
  end

  it "serves the upright webfont locally and removes the Google Fonts dependency" do
    expect(layout).to include('asset_path("notae_sans/notae-sans-variable.woff2")')
    expect(layout).to include('rel: "preload"')
    expect(layout).not_to include("fonts.googleapis.com")
    expect(layout).not_to include("fonts.gstatic.com")
    expect(layout).not_to include("Manrope")
  end

  it "ships valid WOFF2 files through the dedicated Propshaft font path" do
    font_root = Rails.root.join("app/assets/fonts")
    expected_files = %w[
      notae_sans/notae-sans-variable.woff2
      notae_sans/notae-sans-italic-variable.woff2
    ]

    expect(Rails.application.config.assets.paths.map(&:to_s)).to include(font_root.to_s)
    expected_files.each do |relative_path|
      path = font_root.join(relative_path)

      expect(path).to exist
      expect(path.binread(4)).to eq("wOF2")
    end
  end
end
