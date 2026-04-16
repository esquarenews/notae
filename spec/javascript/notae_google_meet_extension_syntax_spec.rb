require "rails_helper"
require "open3"

RSpec.describe "Notae Google Meet extension JavaScript syntax" do
  {
    "background" => Rails.root.join("browser_extensions/notae_google_meet_transcript/background.js"),
    "content" => Rails.root.join("browser_extensions/notae_google_meet_transcript/content.js"),
    "popup" => Rails.root.join("browser_extensions/notae_google_meet_transcript/popup.js")
  }.each do |label, path|
    it "parses the #{label} script successfully" do
      stdout, status = Open3.capture2e("node", "--check", path.to_s)

      expect(status.success?).to be(true), <<~MESSAGE
        Expected #{path} to parse cleanly with node --check.
        Output:
        #{stdout}
      MESSAGE
    rescue Errno::ENOENT
      skip "node is not available in this environment"
    end
  end

  it "keeps the extension wired for popup state, transcript capture, and transcript upload" do
    background = Rails.root.join("browser_extensions/notae_google_meet_transcript/background.js").read
    content = Rails.root.join("browser_extensions/notae_google_meet_transcript/content.js").read
    popup = Nokogiri::HTML(Rails.root.join("browser_extensions/notae_google_meet_transcript/popup.html").read)

    expect(background).to include("notae-meet-start-capture")
    expect(background).to include("notae-meet-stop-capture")
    expect(background).to include("workspaceContextFromUrl")
    expect(background).to include("notae-meet-detected-workspace")
    expect(background).to include("/api/v1/workspaces/")
    expect(background).to include("/ingest_transcript")
    expect(content).to include("aria-live")
    expect(content).to include("notae-meet-transcript-snapshot")
    expect(popup.text).to include("Start capture")
    expect(popup.text).to include("Stop & sync")
    expect(popup.text).to include("Use detected workspace")
  end
end
