require "rails_helper"

RSpec.describe "Account settings styles" do
  it "keeps the account avatar preview and crop frame square" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-account-avatar-panel {\n  flex: 0 0 5rem;\n  width: 5rem;\n  min-width: 5rem;\n  height: 5rem;\n  border-radius: 0.55rem;")
    expect(stylesheet).to include(".notae-avatar-crop-frame {\n  position: relative;\n  width: min(18rem, calc(100vw - 6rem));\n  aspect-ratio: 1;\n  overflow: hidden;\n  border-radius: 0.7rem;")
  end

  it "keeps the account deletion submit button on a destructive high-contrast treatment" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include('button[type="submit"].notae-chip-button.notae-account-delete-button')
    expect(stylesheet).to include("background: linear-gradient(135deg, #ef4444, #dc2626);")
    expect(stylesheet).to include("color: #ffffff;")
    expect(stylesheet).to include("border-color: #dc2626;")
  end
end
