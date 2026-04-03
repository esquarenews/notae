require "rails_helper"
require "open3"

RSpec.describe "EmojiPickerController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/emoji_picker_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "submits the shared icon picker when an emoji is chosen" do
    source = Rails.root.join("app/javascript/controllers/emoji_picker_controller.js").read

    expect(source).to include('static targets = ["form", "input", "searchInput", "option", "section", "emptyState"]')
    expect(source).to include("dataset.iconValue")
    expect(source).to include("this.formTarget.requestSubmit()")
    expect(source).to include("filter()")
    expect(source).to include("dataset.searchText")
    expect(source).to include("section.hidden = !showSection")
  end
end
