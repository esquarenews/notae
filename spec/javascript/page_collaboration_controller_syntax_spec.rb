require "rails_helper"
require "open3"

RSpec.describe "PageCollaborationController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/page_collaboration_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "ignores only the originating block update for the same browser tab" do
    source = Rails.root.join("app/javascript/controllers/page_collaboration_controller.js").read

    expect(source).to include('const storageKey = "notae-client-session-id"')
    expect(source).to include("clientSessionId === this.clientSessionId")
    expect(source).to include("originBlockId === blockId")
    expect(source).to include('new CustomEvent("notae:block-remote-update"')
  end
end
