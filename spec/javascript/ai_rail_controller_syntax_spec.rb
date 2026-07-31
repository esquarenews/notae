require "rails_helper"
require "open3"

RSpec.describe "AiRailController JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/ai_rail_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the visual viewport fallback hooks for compact AI rail mode" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("visualViewport")
    expect(source).to include("is-ai-compact-viewport")
    expect(source).to include("viewportWidth()")
  end

  it "keeps agent update polling without creating a second notification surface" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("const AGENT_UPDATE_POLL_INTERVAL_MS = 15000")
    expect(source).to include("pollAgentUpdates({ force = false } = {})")
    expect(source).to include("syncAgentUpdatePolling({ immediate = false } = {})")
    expect(source).to include("stopAgentUpdatePolling()")
    expect(source).to include("if (!this.railActive()) return")
    expect(source).to include("if (!force && this.agentUpdatePollRequest) return this.agentUpdatePollRequest")
    expect(source).to include("const shouldPollImmediately = immediate && !this.agentUpdateBooting")
    expect(source).to include("this.syncAgentUpdatePolling()")
    expect(source).to include('window.addEventListener("notae:push-received", this.pushReceivedHandler)')
    expect(source).to include('window.removeEventListener("notae:push-received", this.pushReceivedHandler)')
    expect(source).to include("this.pollAgentUpdates({ force: true })")
    expect(source).to include('const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"')
    expect(source).to include("this.preference(AI_RAIL_COLLAPSED_PREFERENCE_KEY, false)")
    expect(source).not_to include("agentToast")
    expect(source).not_to include("showAgentToast")
  end

  it "keeps ordered timeline insertion for polled agent updates" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("insertTimelineElement(element)")
    expect(source).to include('querySelectorAll(".notae-ai-thread-entry")')
    expect(source).to include("existingTimestamp > newTimestamp")
  end

  it "does not retain the removed AI alert toast or its focus behavior" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).not_to include("latestUnseenAgentUpdateElement")
    expect(source).not_to include("queueAgentUpdateFocus")
    expect(source).not_to include("is-recently-focused")
  end

  it "marks agent work busy and restores the prompt after a failed submission" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read
    submit_start_handler = source.match(/submitStart\(event\) \{(?<body>.*?)\n  \}/m)&.[](:body)

    expect(source).to include('this.threadTarget.setAttribute("aria-busy", "true")')
    expect(source).to include('this.threadTarget.setAttribute("aria-busy", "false")')
    expect(source).to include("event.detail?.success === false")
    expect(source).to include("this.promptInputTarget.value = this.pendingPrompt")
    expect(submit_start_handler).to be_present
    expect(submit_start_handler).not_to include('this.promptInputTarget.value = ""')
  end

  it "submits with Enter and reserves Shift+Enter for a new line" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read
    shortcut_handler = source.match(/submitOnShortcut\(event\) \{(?<body>.*?)\n  \}/m)&.[](:body)

    expect(shortcut_handler).to be_present
    expect(shortcut_handler).to include('if (event.key !== "Enter") return')
    expect(shortcut_handler).to include("if (event.shiftKey) return")
    expect(shortcut_handler).not_to include("event.metaKey || event.ctrlKey")
    expect(shortcut_handler).to include("event.preventDefault()")
    expect(shortcut_handler).to include("form.requestSubmit")
  end
end
