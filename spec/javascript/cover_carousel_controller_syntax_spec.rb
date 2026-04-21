require "rails_helper"
require "open3"

RSpec.describe "CoverCarouselController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/cover_carousel_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "cycles between grouped cover preset screens and drives the Unsplash modal" do
    source = Rails.root.join("app/javascript/controllers/cover_carousel_controller.js").read

    expect(source).to include("static targets = [")
    expect(source).to include("\"unsplashDialog\"")
    expect(source).to include("static values = {")
    expect(source).to include("unsplashUrl: String")
    expect(source).to include("this.goTo(this.index - 1)")
    expect(source).to include("this.goTo(this.index + 1)")
    expect(source).to include("event.params.index")
    expect(source).to include("screen.hidden = !isActive")
    expect(source).to include("dot.setAttribute(\"aria-current\", isActive ? \"true\" : \"false\")")
    expect(source).to include("showModal()")
    expect(source).to include("loadUnsplashPage")
    expect(source).to include("prefetchNextPage")
    expect(source).to include("requestSubmit()")
  end

  it "keeps no-file upload submits local so the picker does not hang" do
    source = Rails.root.join("app/javascript/controllers/cover_carousel_controller.js").read

    expect(source).to include("\"uploadInput\"")
    expect(source).to include("\"uploadError\"")
    expect(source).to include("startUploadSubmit(event)")
    expect(source).to include("if (!this.hasSelectedUploadFile())")
    expect(source).to include("event.preventDefault()")
    expect(source).to include("showUploadError(\"Choose an image before uploading.\")")
    expect(source).to include("this.uploadSubmitTarget.disabled = true")
    expect(source).to include("this.uploadSpinnerTarget.hidden = false")
  end
end
