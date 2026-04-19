require "rails_helper"
require "open3"

RSpec.describe "AvatarCropController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/avatar_crop_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "supports modal cropping, drag repositioning, zoom, and file replacement" do
    source = Rails.root.join("app/javascript/controllers/avatar_crop_controller.js").read

    expect(source).to include("dialogTarget.showModal()")
    expect(source).to include("URL.createObjectURL")
    expect(source).to include("window.requestAnimationFrame")
    expect(source).to include("startDrag(event)")
    expect(source).to include("drag(event)")
    expect(source).to include("stopDrag(event)")
    expect(source).to include("setPointerCapture")
    expect(source).to include("releasePointerCapture")
    expect(source).to include("canvas.toBlob")
    expect(source).to include("new DataTransfer()")
    expect(source).to include("this.inputTarget.files = transfer.files")
    expect(source).to include("new File([blob]")
    expect(source).to include("renderPreview(file)")
    expect(source).to include("this.previewPanelTarget.replaceChildren(image)")
    expect(source).to include("inputTarget?.files?.[0]")
    expect(source).to include("type: \"image/png\"")
    expect(source).to include("this.element.requestSubmit()")
  end
end
