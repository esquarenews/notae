require "rails_helper"
require "open3"

RSpec.describe "bin/deploy-production" do
  let(:script_path) { Rails.root.join("bin/deploy-production") }

  it "has valid bash syntax" do
    stdout, status = Open3.capture2e("bash", "-n", script_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{script_path} to pass bash -n.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "bash is not available in this environment"
  end

  it "documents the production deploy defaults and safety controls" do
    stdout, status = Open3.capture2e(script_path.to_s, "--help")

    expect(status.success?).to be(true)
    expect(stdout).to include("APP_ROOT=/home/esquarenews/apps/notae")
    expect(stdout).to include("ENV_FILE=/etc/notae/notae.env")
    expect(stdout).to include("RUN_TESTS=1")
    expect(stdout).to include("RESTART_TIMERS=0")
    expect(stdout).to include('OPTIONAL_TIMERS="notae-kalendarium-sync.timer"')
    expect(stdout).to include('OPTIONAL_ONESHOTS="notae-kalendarium-sync.service"')
    expect(stdout).not_to include("epistularium", "calendar/mail")
  end

  it "only schedules calendar sync units by default after retiring email" do
    source = script_path.read.sub(/^main "\$@"\s*\z/, "")
    stdout, status = Open3.capture2e(
      { "OPTIONAL_TIMERS" => nil, "OPTIONAL_ONESHOTS" => nil },
      "bash", "-c", source + "\n" + 'printf "%s\\n" "$OPTIONAL_TIMERS" "$OPTIONAL_ONESHOTS"'
    )

    expect(status.success?).to be(true), stdout
    expect(stdout.lines.map(&:strip)).to eq([
      "notae-kalendarium-sync.timer",
      "notae-kalendarium-sync.service"
    ])
  end

  it "checks systemd unit existence through LoadState resolution" do
    source = script_path.read

    expect(source).to include("systemctl show")
    expect(source).to include("-p LoadState --value")
    expect(source).to include('[[ "$load_state" == "loaded" ]]')
    expect(source).not_to include("list-unit-files")
  end
end
