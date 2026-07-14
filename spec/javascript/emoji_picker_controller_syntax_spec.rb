require "rails_helper"
require "open3"
require "json"
require "base64"

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
    expect(source).to include("emojiSearchMatches(searchText, query, { allowTypos: false })")
    expect(source).to include("emojiSearchMatches(searchText, query, { allowTypos })")
    expect(source).to include("section.hidden = !showSection")
  end

  it "matches plain language, plurals, multiple terms, and small typos" do
    search_module_path = Rails.root.join("app/javascript/controllers/emoji_search.js")
    encoded_module = Base64.strict_encode64(search_module_path.read)
    module_url = "data:text/javascript;base64,#{encoded_module}"
    script = <<~JAVASCRIPT
      import { emojiSearchMatches } from #{module_url.to_json}

      const cases = [
        ["star glowing star", "star", true],
        ["cat face pet", "pets", true],
        ["birthday cake celebration", "birthdy", true],
        ["red car automobile", "red automobile", true],
        ["teacher school", "weather", false],
        ["cat face pet", "weather", false]
      ]

      for (const [searchText, query, expected] of cases) {
        const actual = emojiSearchMatches(searchText, query)
        if (actual !== expected) {
          throw new Error(`${query}: expected ${expected}, received ${actual}`)
        }
      }

      if (emojiSearchMatches("birthday cake", "birthdy", { allowTypos: false })) {
        throw new Error("Strict matching unexpectedly accepted a typo")
      }
    JAVASCRIPT

    stdout, status = Open3.capture2e(
      "node",
      "--input-type=module",
      "--eval",
      script
    )

    expect(status.success?).to be(true), <<~MESSAGE
      Expected emoji search matching cases to pass.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end
end
