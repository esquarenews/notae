require "rails_helper"
require "open3"

RSpec.describe "Archive game controller JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/archive_game_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the game loop interactive and goal-driven" do
    source = Rails.root.join("app/javascript/controllers/archive_game_controller.js").read

    expect(source).to include('import * as THREE from "three"')
    expect(source).to include("FRAGMENT_COUNT = 7")
    expect(source).to include("PLAY_BOUNDS = Object.freeze")
    expect(source).to include("clampVectorToPlayBounds")
    expect(source).to include("SENTINEL_HIT_DAMAGE")
    expect(source).to include("LEVEL_SPEED_STEP")
    expect(source).to include("TOUCH_DRAG_THRESHOLD")
    expect(source).to include("touchMoveVector")
    expect(source).to include("randomizeFragments()")
    expect(source).to include("advanceLevel()")
    expect(source).to include("toggleSound()")
    expect(source).to include("createOscillator")
    expect(source).to include("screenFlash")
    expect(source).to include("eventCue")
    expect(source).to include("showEventCue")
    expect(source).to include("createWorldFeedback")
    expect(source).to include("updateFeedbackEffects")
    expect(source).to include("DOCUMENT SECURED")
    expect(source).to include("INTEGRITY HIT")
    expect(source).to include("handlePointerdown")
    expect(source).to include("handlePointermove")
    expect(source).to include("handlePointerup")
    expect(source).to include("setPointerTargetFromEvent")
    expect(source).to include("captureTouchPointer")
    expect(source).to include("releaseTouchPointer")
    expect(source).to include("setPointerCapture")
    expect(source).to include("releasePointerCapture")
    expect(source).to include("checkWin()")
    expect(source).to include("Sentinel breach.")
    expect(source).to include("The archive shifts faster.")
  end
end
