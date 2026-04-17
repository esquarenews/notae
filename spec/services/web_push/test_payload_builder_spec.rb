require "rails_helper"

RSpec.describe WebPush::TestPayloadBuilder do
  include ActiveSupport::Testing::TimeHelpers

  it "builds a deep-linking test payload for notification settings" do
    user = User.create!(email: "test-payload-builder@example.com", password: "password123", time_zone: "Australia/Melbourne")
    workspace = Workspace.create!(name: "Test payload workspace", slug: "test-payload-workspace")

    travel_to Time.zone.parse("2026-04-17 09:45:00") do
      payload = described_class.new(user: user, workspace: workspace).call

      expect(payload[:title]).to eq("Notae test notification")
      expect(payload[:body]).to include("Push notifications are working on this device for Test payload workspace.")
      expect(payload[:body]).to include("Fri 17 Apr")
      expect(payload[:url]).to eq("/w/test-payload-workspace/settings/notifications")
      expect(payload[:tag]).to eq("notae-test-push-#{workspace.id}")
    end
  end
end
