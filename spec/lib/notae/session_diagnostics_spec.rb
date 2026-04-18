require "rails_helper"

RSpec.describe Notae::SessionDiagnostics do
  describe ".approximate_payload_bytes" do
    it "returns a positive payload size for a typical session hash" do
      bytes = described_class.approximate_payload_bytes(
        "session_id" => "abc123",
        "notae_last_workspace_slug" => "personal",
        "flash" => { "alert" => "expired" }
      )

      expect(bytes).to be > 0
    end
  end

  describe ".event_payload" do
    it "captures request and session metadata without raw session values" do
      request = instance_double(
        ActionDispatch::Request,
        request_id: "req-123",
        request_method: "POST",
        fullpath: "/w/personal/pages/1/comments",
        referer: "https://notae.example.com/w/personal",
        user_agent: "RSpec Browser",
        remote_ip: "127.0.0.1"
      )
      user = instance_double(User, id: "user-1")

      payload = described_class.event_payload(
        request: request,
        session: {
          "session_id" => "abc123",
          "flash" => { "alert" => "expired" },
          "warden.user.user.key" => [ "sensitive" ]
        },
        current_user: user,
        reason: "invalid_authenticity_token"
      )

      expect(payload[:reason]).to eq("invalid_authenticity_token")
      expect(payload[:user_id]).to eq("user-1")
      expect(payload[:session_keys]).to include("session_id", "flash")
      expect(payload[:session_keys]).not_to include("warden.user.user.key")
      expect(payload[:approximate_session_bytes]).to be > 0
    end
  end
end
