require "rails_helper"

RSpec.describe User, type: :model do
  describe "#platform_admin?" do
    it "allows explicit super admins" do
      user = described_class.new(email: "super-admin@example.com", super_admin: true)

      expect(user).to be_platform_admin
    end

    it "allows case-insensitive env allowlisted emails" do
      user = described_class.new(email: "AllowListed@example.com")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("NOTAE_PLATFORM_ADMIN_EMAILS", "").and_return("other@example.com, allowlisted@example.com")

      expect(user).to be_platform_admin
    end

    it "rejects normal users" do
      user = described_class.new(email: "normal-user@example.com")

      expect(user).not_to be_platform_admin
    end
  end
end
