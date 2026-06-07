require "rails_helper"

RSpec.describe "Admin styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "lets admin pages use the full settings shell instead of the empty settings nav column" do
    expect(stylesheet).to include("main.notae-content.notae-admin-content {\n  max-width: min(1480px, calc(100vw - 2rem));\n}")
    expect(stylesheet).to include(".notae-admin-dashboard-shell {\n  width: 100%;\n  display: grid;")
    expect(stylesheet).to include(".notae-admin-table {\n  width: 100%;\n  min-width: 1180px;")
    expect(stylesheet).to include(".notae-admin-limit-grid {\n  display: grid;\n  grid-template-columns: repeat(3, minmax(0, 1fr));")
  end
end
