require "rails_helper"

RSpec.describe Openai::CredentialResolver do
  before do
    allow(ENV).to receive(:[]).and_call_original
  end

  it "prefers a nonblank per-user key over the server key" do
    user = instance_double(User, openai_api_key: "  sk-user-secret  ")
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-server-secret")

    expect(described_class.resolve(user: user)).to eq("sk-user-secret")
  end

  it "falls back to the server key when the user key is blank" do
    user = instance_double(User, openai_api_key: "  ")
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("  sk-server-secret  ")

    expect(described_class.call(user: user)).to eq("sk-server-secret")
    expect(described_class.configured?(user: user)).to be(true)
  end

  it "can use the server key when there is no user" do
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-server-secret")

    expect(described_class.resolve(user: nil)).to eq("sk-server-secret")
  end

  it "returns nil when neither credential is configured" do
    user = instance_double(User, openai_api_key: nil)
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("  ")

    expect(described_class.resolve(user: user)).to be_nil
    expect(described_class.configured?(user: user)).to be(false)
  end

  it "falls back without logging credentials when a saved key cannot be decrypted" do
    user = instance_double(User)
    allow(user).to receive(:openai_api_key).and_raise(ActiveRecord::Encryption::Errors::Decryption)
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-server-secret")
    allow(Rails.logger).to receive(:warn)

    expect(described_class.resolve(user: user)).to eq("sk-server-secret")
    expect(Rails.logger).not_to have_received(:warn)
  end
end
