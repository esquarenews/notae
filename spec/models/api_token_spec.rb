require "rails_helper"
require "base64"

RSpec.describe ApiToken, type: :model do
  it "generates a token with at least 32 bytes entropy" do
    user = User.create!(email: "api-token-entropy@example.com", password: "password123")

    api_token = described_class.create!(user: user, name: "Mobile")
    padded = api_token.token + ("=" * ((4 - (api_token.token.length % 4)) % 4))
    decoded = Base64.urlsafe_decode64(padded)

    expect(decoded.bytesize).to be >= 32
  end

  it "only includes non-revoked and non-expired records in active scope" do
    user = User.create!(email: "api-token-active-scope@example.com", password: "password123")

    active = described_class.create!(user: user, name: "Active")
    revoked = described_class.create!(user: user, name: "Revoked")
    expired = described_class.create!(user: user, name: "Expired")

    revoked.update!(revoked_at: Time.current)
    expired.update!(expires_at: 1.minute.ago)

    expect(described_class.active).to include(active)
    expect(described_class.active).not_to include(revoked)
    expect(described_class.active).not_to include(expired)
  end
end
