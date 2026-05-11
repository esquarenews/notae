require "rails_helper"

RSpec.describe Notae::OutboundNetworkGuard do
  it "allows ordinary public hosts and blocks local or private targets" do
    expect(described_class.public_host?("smtp.example.com")).to be(true)
    expect(described_class.public_host?("localhost")).to be(false)
    expect(described_class.public_host?("app.local")).to be(false)
    expect(described_class.public_host?("127.0.0.1")).to be(false)
    expect(described_class.public_host?("10.0.0.25")).to be(false)
    expect(described_class.public_host?("[::1]")).to be(false)
  end

  it "allows operators to opt into private endpoints for self-hosted deployments" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NOTAE_ALLOW_PRIVATE_NETWORK_ENDPOINTS", nil).and_return("true")

    expect(described_class.public_host?("127.0.0.1")).to be(true)
  end
end
