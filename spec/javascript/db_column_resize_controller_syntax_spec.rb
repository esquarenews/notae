require "rails_helper"
require "open3"

RSpec.describe "DbColumnResizeController JavaScript" do
  let(:controller_path) { Rails.root.join("app/javascript/controllers/db_column_resize_controller.js") }

  it "parses successfully" do
    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "measures the rendered header instead of the unreliable col element when resizing starts" do
    source = controller_path.read

    expect(source).to include("const measuredWidth = header.getBoundingClientRect().width")
    expect(source).not_to include("(targetColumn || header).getBoundingClientRect().width")
    expect(source).to include("const nextWidth = this.clampWidth(this.startWidth + delta, minimumWidth)")
  end

  it "applies the first pointer movement relative to the rendered header width" do
    harness_path = Rails.root.join("spec/javascript/db_column_resize_controller_harness.mjs")
    stdout, status = Open3.capture2e("node", harness_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected the first resize movement to track the pointer without jumping to the maximum.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end
end
