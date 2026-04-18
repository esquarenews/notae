require "rails_helper"

RSpec.describe ApiTokenAuditEvent, type: :model do
  it "requires a supported event type" do
    user = User.create!(email: "api-token-audit-user@example.com", password: "password123")
    token = ApiToken.create!(user: user, name: "Audit token")
    event = described_class.new(api_token: token, user: user, event_type: "unexpected")

    expect(event).not_to be_valid
    expect(event.errors[:event_type]).to include("is not included in the list")
  end
end
