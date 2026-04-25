require "rails_helper"
require "open3"

RSpec.describe "Global shortcuts controller JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/global_shortcuts_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the archive game behind a typed easter egg sequence" do
    source = Rails.root.join("app/javascript/controllers/global_shortcuts_controller.js").read

    expect(source).to include('this.easterEggSequence === "archive"')
    expect(source).to include("this.archiveGameMatchesQuery(query)")
    expect(source).to include('"archive".startsWith(query)')
    expect(source).to include('query.length < 3')
    expect(source).to include('title: "The Archive"')
    expect(source).to include("openArchiveGame()")
    expect(source).to include('/w/${encodeURIComponent(workspaceSlug)}/_archive')
    expect(source).to include('window.location.pathname.match(/^\\/w\\/([^/]+)/)')
    expect(source).to include("interactiveElement(event.target)")
  end
end
