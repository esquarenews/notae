require "rails_helper"
require "open3"

RSpec.describe "PreferencesController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/preferences_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "updates dependent preference UI state without a full page reload" do
    source = Rails.root.join("app/javascript/controllers/preferences_controller.js").read

    expect(source).to include("handleThemeChange")
    expect(source).to include("applyThemeClass")
    expect(source).to include("syncTimeZoneInputState")
    expect(source).to include("syncOpenLinksPreference")
    expect(source).to include("notae-theme-dark")
    expect(source).to include("linkPreferencesOpenLinksInNewWindowValue")
    expect(source).to include("timeZoneSelectTarget.disabled")
  end
end
