require "rails_helper"
require "open3"

RSpec.describe "Meeting bot worker JavaScript" do
  it "parses successfully" do
    worker_path = Rails.root.join("services/meeting_bot_worker/worker.mjs")
    core_path = Rails.root.join("services/meeting_bot_worker/lib/core.mjs")

    [ worker_path, core_path ].each do |path|
      stdout, status = Open3.capture2e("node", "--check", path.to_s)

      expect(status.success?).to be(true), <<~MESSAGE
        Expected #{path} to parse cleanly with node --check.
        Output:
        #{stdout}
      MESSAGE
    end
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "contains the claim, heartbeat, and transcript completion workflow" do
    source = Rails.root.join("services/meeting_bot_worker/worker.mjs").read

    expect(source).to include("claimNextRun")
    expect(source).to include("sendHeartbeat")
    expect(source).to include("transcript_complete_path")
    expect(source).to include("Ask to join")
    expect(source).to include("Turn on captions")
    expect(source).to include("captureArtifacts")
    expect(source).to include("artifact_screenshot_path")
    expect(source).to include("google_meet")
    expect(source).to include("claim polling failed")
    expect(source).to include("Expected JSON from")
    expect(source).to include("MEETING_BOT_MINIMUM_JOIN_DIAGNOSIS_MS")
    expect(source).to include("Continue without microphone and camera")
    expect(source).to include("stage=")
    expect(source).to include("prejoin_ready")
    expect(source).to include("grantPermissions")
  end

  it "keeps transcript collector logic stable" do
    core_path = Rails.root.join("services/meeting_bot_worker/lib/core.mjs")
    command = <<~JS
      import { buildAbsoluteUrl, TranscriptCollector, classifyGoogleMeetJoinText } from #{core_path.to_s.inspect};

      const collector = new TranscriptCollector({ startedAt: 0 });
      collector.addEntries([{ speaker_name: "Errol", text: "Opening update" }], 1_000);
      collector.addEntries([{ speaker_name: "Errol", text: "Opening update" }], 2_000);
      collector.addEntries([{ speaker_name: "Errol", text: "Opening update with extra detail" }], 3_000);

      const output = {
        url: buildAbsoluteUrl("https://notae.example", "/internal/meeting_bot_runs/claim"),
        utteranceCount: collector.utterances.length,
        transcript: collector.transcriptText(),
        waitingState: classifyGoogleMeetJoinText("You asked to join. Someone in the call should let you in soon."),
        readyState: classifyGoogleMeetJoinText("Ready to join Choose how you want to join"),
        hostWaitingState: classifyGoogleMeetJoinText("Please wait until a meeting host brings you into the call"),
        deniedState: classifyGoogleMeetJoinText("Your request to join was denied."),
        joinedState: classifyGoogleMeetJoinText("Leave call Turn on captions")
      };
      console.log(JSON.stringify(output));
    JS

    stdout, status = Open3.capture2e("node", "--input-type=module", "-e", command)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected worker core helper check to succeed.
      Output:
      #{stdout}
    MESSAGE

    payload = JSON.parse(stdout)
    expect(payload.fetch("url")).to eq("https://notae.example/internal/meeting_bot_runs/claim")
    expect(payload.fetch("utteranceCount")).to eq(1)
    expect(payload.fetch("transcript")).to include("Opening update with extra detail")
    expect(payload.fetch("waitingState")).to include("state" => "waiting")
    expect(payload.fetch("readyState")).to include("state" => "waiting")
    expect(payload.fetch("hostWaitingState")).to include("state" => "waiting")
    expect(payload.fetch("deniedState")).to include("state" => "denied")
    expect(payload.fetch("joinedState")).to include("state" => "joined")
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end
end
