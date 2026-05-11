require "rails_helper"

RSpec.describe Notae::RequestRateLimiter do
  around do |example|
    Rails.cache.clear
    described_class.reset!
    example.run
    Rails.cache.clear
    described_class.reset!
  end

  it "allows requests until the configured limit is exceeded" do
    expect(described_class.consume!(name: "spec", discriminator: "client", limit: 2, period: 1.minute)).to be(true)
    expect(described_class.consume!(name: "spec", discriminator: "client", limit: 2, period: 1.minute)).to be(true)
    expect(described_class.consume!(name: "spec", discriminator: "client", limit: 2, period: 1.minute)).to be(false)
  end
end
