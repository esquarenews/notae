require "rails_helper"

RSpec.describe "Admin styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "lets admin pages use the full settings shell instead of the empty settings nav column" do
    expect(stylesheet).to include(".notae-content.notae-admin-content {\n  max-width: 1180px;\n}")
    expect(stylesheet).to include(".notae-admin-shell {\n  grid-template-columns: minmax(0, 1fr);\n}")
    expect(stylesheet).to include(".notae-admin-shell .notae-ai-analytics-grid {\n  grid-template-columns: repeat(auto-fit, minmax(min(100%, 12rem), 1fr));\n}")
    expect(stylesheet).to include(".notae-admin-shell .notae-utility-title {\n  font-size: clamp(1.75rem, 2vw, 2.25rem);\n  overflow-wrap: anywhere;\n  word-break: break-word;\n}")
  end
end
