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

  it "keeps agent update polling, toast handling, and the expanded desktop rail default" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("AGENT_UPDATE_POLL_INTERVAL_MS")
    expect(source).to include("AGENT_UPDATE_TOAST_DURATION_MS")
    expect(source).to include("pollAgentUpdates({ force = false } = {})")
    expect(source).to include("syncAgentUpdatePolling({ immediate = false } = {})")
    expect(source).to include("stopAgentUpdatePolling()")
    expect(source).to include("if (!this.railActive()) return")
    expect(source).to include("if (!force && this.agentUpdatePollRequest) return this.agentUpdatePollRequest")
    expect(source).to include("const shouldPollImmediately = immediate && !this.agentUpdateBooting")
    expect(source).to include("this.syncAgentUpdatePolling()")
    expect(source).to include("showAgentToast(count)")
    expect(source).to include("statusBarAvailable()")
    expect(source).to include("document.querySelector(\".notae-shell-status-bar\")")
    expect(source).to include('const AI_RAIL_COLLAPSED_PREFERENCE_KEY = "notae-ai-rail-collapsed-v2"')
    expect(source).to include("this.preference(AI_RAIL_COLLAPSED_PREFERENCE_KEY, false)")
    expect(source).to match(/window\.setTimeout\(\(\) => \{\s*this\.dismissCurrentAgentToast\(\)/m)
  end

  it "keeps ordered timeline insertion for polled agent updates" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("insertTimelineElement(element)")
    expect(source).to include('querySelectorAll(".notae-ai-thread-entry")')
    expect(source).to include("existingTimestamp > newTimestamp")
  end

  it "reopens the rail on the newest unseen agent update instead of a random thread position" do
    source = Rails.root.join("app/javascript/controllers/ai_rail_controller.js").read

    expect(source).to include("latestUnseenAgentUpdateElement()")
    expect(source).to include("queueAgentUpdateFocus(targetUpdateId)")
    expect(source).to include("scrollAgentUpdateIntoView(updateId)")
    expect(source).to include('scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" })')
  end
end
