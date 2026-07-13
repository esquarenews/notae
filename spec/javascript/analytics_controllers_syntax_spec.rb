require "rails_helper"
require "open3"

RSpec.describe "Analytics Stimulus controllers" do
  it "parses the activity tracker and filter controllers with Node" do
    %w[analytics_tracker_controller.js analytics_filters_controller.js].each do |filename|
      path = Rails.root.join("app/javascript/controllers", filename)
      _stdout, stderr, status = Open3.capture3("node", "--check", path.to_s)

      expect(status.success?).to be(true), <<~MESSAGE
        Expected #{path} to parse cleanly with node --check.
        #{stderr}
      MESSAGE
    end
  end

  it "keeps short hidden-tab intervals and client samples idempotent" do
    source = Rails.root.join("app/javascript/controllers/analytics_tracker_controller.js").read

    expect(source).to include("flushPartial({ allowHidden: true })")
    expect(source).to include("turbo:before-visit")
    expect(source).to include("sample_id: this.sampleId()")
    expect(source).to include("keepalive")
    expect(source).to include('document.addEventListener("focusin", this.handlePassiveInteraction, true)')
  end

  it "starts a fresh sampling interval after idle or unfocused time" do
    controller_path = Rails.root.join("app/javascript/controllers/analytics_tracker_controller.js")
    harness_path = Rails.root.join("spec/javascript/analytics_tracker_timing_harness.mjs")
    _stdout, stderr, status = Open3.capture3("node", harness_path.to_s, controller_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected the analytics tracker to exclude idle and unfocused time when sampling resumes.
      #{stderr}
    MESSAGE
  end
end
