require "rails_helper"
require "open3"

RSpec.describe "Nota Maze game controller JavaScript syntax" do
  it "parses successfully" do
    controller_path = Rails.root.join("app/javascript/controllers/nota_maze_game_controller.js")

    stdout, status = Open3.capture2e("node", "--check", controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{controller_path} to parse cleanly with node --check.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "node is not available in this environment"
  end

  it "keeps the Pacman-style loop playable and Notae-themed" do
    source = Rails.root.join("app/javascript/controllers/nota_maze_game_controller.js").read

    expect(source).to include("MAZE_LAYOUTS = Object.freeze")
    expect(source).to include("BUG_TYPES = Object.freeze")
    expect(source).to include("stale task")
    expect(source).to include("sync error")
    expect(source).to include("blocker")
    expect(source).to include("POWER_DURATION_MS")
    expect(source).to include("SAFE_START_MS = 2600")
    expect(source).to include("TURN_ASSIST_DISTANCE")
    expect(source).to include("LEVEL_SPEED_STEP")
    expect(source).to include("applyResponsiveTurn")
    expect(source).to include("this.keys.delete(key)")
    expect(source).not_to include("keyboardDirection()")
    expect(source).to include("chooseBugDirection")
    expect(source).to include("firstStepToward")
    expect(source).to include("collectCurrentTile")
    expect(source).to include("handleBugHit")
    expect(source).to include("checkLevelClear")
    expect(source).to include("LEVEL CLEARED")
    expect(source).to include("Sound On")
    expect(source).to include("Sound Off")
    expect(source).to include("playSound")
    expect(source).to include("handlePointerdown")
    expect(source).to include("queueDirectionFromVector")
    expect(source).to include("prepareOverlayFont")
    expect(source).to include("document.fonts.load")
    expect(source).to include('800 32px "Notae Sans"')
    expect(source).not_to include("32px system-ui")
  end
end
