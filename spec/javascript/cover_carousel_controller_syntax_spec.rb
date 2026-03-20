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

  it "cycles between grouped cover preset screens" do
    source = Rails.root.join("app/javascript/controllers/cover_carousel_controller.js").read

    expect(source).to include("static targets = [\"screen\", \"label\", \"dot\"]")
    expect(source).to include("static values = { initialIndex: Number }")
    expect(source).to include("this.goTo(this.index - 1)")
    expect(source).to include("this.goTo(this.index + 1)")
    expect(source).to include("event.params.index")
    expect(source).to include("screen.hidden = !isActive")
    expect(source).to include("dot.setAttribute(\"aria-current\", isActive ? \"true\" : \"false\")")
  end
end
