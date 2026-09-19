require "rails_helper"

RSpec.describe "AI rail styles" do
  it "keeps the title on one line and lets the controls use the remaining width" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(<<~CSS)
      .notae-ai-head-title {
        flex: 0 0 auto;
        white-space: nowrap;
      }
    CSS
    expect(stylesheet).to include(<<~CSS)
      .notae-ai-head-controls {
        display: inline-flex;
        flex: 1 1 auto;
        align-items: center;
        justify-content: flex-end;
        gap: 0.3rem;
        min-width: 0;
      }
    CSS
    expect(stylesheet).to include("max-width: 6.5rem;")
  end
end
