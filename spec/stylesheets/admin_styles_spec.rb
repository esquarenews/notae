require "rails_helper"

RSpec.describe "Admin styles" do
  let(:stylesheet) { Rails.root.join("app/assets/stylesheets/application.css").read }

  it "lets admin pages use the full settings shell instead of the empty settings nav column" do
    expect(stylesheet).to include(".notae-shell.notae-shell-admin {\n  grid-template-columns: 238px minmax(0, 1fr);\n}")
    expect(stylesheet).to include("main.notae-content.notae-admin-content {\n  max-width: min(1480px, calc(100vw - 2rem));\n}")
    expect(stylesheet).to include(".notae-admin-dashboard-shell {\n  width: 100%;\n  display: grid;")
    expect(stylesheet).to include(".notae-admin-summary-grid article:nth-child(1)")
    expect(stylesheet).to include("border-left: 3px solid color-mix")
    expect(stylesheet).to include(".notae-admin-user-tier-row > td:first-child {\n  border-left: 4px solid var(--notae-admin-user-tier-accent);\n}")
    expect(stylesheet).to include(".notae-admin-user-tier-trial")
    expect(stylesheet).to include(".notae-admin-user-tier-starter")
    expect(stylesheet).to include(".notae-admin-user-tier-team")
    expect(stylesheet).to include(".notae-admin-user-tier-business")
    expect(stylesheet).to include(".notae-admin-user-tier-cancelled")
    expect(stylesheet).to include(".notae-admin-table {\n  width: 100%;\n  min-width: 1180px;")
    expect(stylesheet).to include(".notae-admin-limit-grid {\n  display: grid;\n  grid-template-columns: repeat(3, minmax(0, 1fr));")
  end
end
