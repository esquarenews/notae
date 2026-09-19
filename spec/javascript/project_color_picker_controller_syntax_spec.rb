require "rails_helper"
require "open3"

RSpec.describe "ProjectColorPickerController JavaScript syntax" do
  let(:controller_path) { Rails.root.join("app/javascript/controllers/project_color_picker_controller.js") }

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

  it "opens the native color picker and saves the selected project color" do
    source = controller_path.read

    expect(source).to include('static targets = ["input", "swatch"]')
    expect(source).to include('typeof this.inputTarget.showPicker === "function"')
    expect(source).to include("this.inputTarget.showPicker()")
    expect(source).to include("this.inputTarget.click()")
    expect(source).to include('swatch.style.setProperty("--kal-color", this.inputTarget.value)')
    expect(source).to include("this.element.requestSubmit()")
  end
end
