require "rails_helper"

RSpec.describe Billing::FatZebraWebhookProcessor do
  it "ignores unsupported events while keeping an idempotency record" do
    raw_body = {
      event: "purchase:success",
      payload: {
        id: "071-P-245JAGI0",
        reference: "notae-ignored"
      }
    }.to_json

    event = described_class.new(raw_body: raw_body, headers: {}, verified: false).call

    expect(event).to be_ignored
    expect(event.event_name).to eq("purchase:success")
    expect(event.provider_object_id).to eq("071-P-245JAGI0")
  end

  it "ignores supported payment-plan events that do not match a subscription" do
    raw_body = {
      event: "payment_plan:suspended",
      payload: {
        id: "unknown-plan",
        customer: "unknown-customer",
        status: "Suspended"
      }
    }.to_json

    event = described_class.new(raw_body: raw_body, headers: {}, verified: false).call

    expect(event).to be_ignored
  end
end
