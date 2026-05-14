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

  it "blocks hostnames that resolve to private addresses before outbound calls" do
    private_address = instance_double(Addrinfo, ip_address: "10.0.0.5")
    public_address = instance_double(Addrinfo, ip_address: "8.8.8.8")

    allow(Addrinfo).to receive(:getaddrinfo).with("private.example.com", nil).and_return([ private_address ])
    allow(Addrinfo).to receive(:getaddrinfo).with("public.example.com", nil).and_return([ public_address ])

    expect(described_class.public_resolved_host?("private.example.com")).to be(false)
    expect(described_class.public_resolved_host?("public.example.com")).to be(true)
  end
end
