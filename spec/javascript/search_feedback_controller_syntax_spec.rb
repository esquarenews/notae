require "rails_helper"
require "open3"

RSpec.describe "SearchFeedbackController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/search_feedback_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "marks search forms and submit buttons busy while a search is submitting" do
    source = Rails.root.join("app/javascript/controllers/search_feedback_controller.js").read

    expect(source).to include("static targets = [\"status\", \"submit\"]")
    expect(source).to include("this.element.classList.toggle(\"is-searching\", loading)")
    expect(source).to include("this.element.setAttribute(\"aria-busy\", loading ? \"true\" : \"false\")")
    expect(source).to include("this.statusTarget.hidden = !loading")
    expect(source).to include("submit.toggleAttribute(\"disabled\", loading)")
    expect(source).to include("submit.setAttribute(\"aria-busy\", loading ? \"true\" : \"false\")")
    expect(source).to include("if (submit instanceof HTMLInputElement) {\n      return\n    }")
  end
end
