require "rails_helper"

RSpec.describe AutomationControl, type: :model do
  it "acts as a singleton kill switch" do
    control = described_class.current
    expect(control.enabled).to eq(true)

    control.pause!(reason: "Testing kill switch")
    expect(control.reload.enabled).to eq(false)
    expect(control.pause_reason).to eq("Testing kill switch")

    control.resume!
    expect(control.reload.enabled).to eq(true)
    expect(control.pause_reason).to be_nil
  end
end
