require "rails_helper"
require "open3"

RSpec.describe "DocumentPickerController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/document_picker_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "uses debounced same-origin fetches and submits the hidden target id" do
    source = Rails.root.join("app/javascript/controllers/document_picker_controller.js").read

    expect(source).to include("SEARCH_DEBOUNCE_MS")
    expect(source).to include("window.setTimeout")
    expect(source).to include("new AbortController()")
    expect(source).to include("credentials: \"same-origin\"")
    expect(source).to include("\"X-Requested-With\": \"XMLHttpRequest\"")
    expect(source).to include("this.hiddenInputTarget.value = targetId")
    expect(source).to include("this.hiddenInputTarget.form?.requestSubmit()")
  end
end
