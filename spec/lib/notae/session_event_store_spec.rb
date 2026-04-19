require "rails_helper"

RSpec.describe Notae::SessionEventStore do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "records and returns recent normalized events per user" do
    described_class.record!(
      user_id: "user-1",
      event: {
        reason: "signed_in",
        session_store: "cookie_store",
        path: "/users/sign_in",
        request_method: "POST",
        approximate_session_bytes: 128,
        session_key_count: 4,
        recorded_at: "2026-04-19T15:00:00Z"
      }
    )

    event = described_class.fetch(user_id: "user-1").first

    expect(event).to include(
      reason: "signed_in",
      session_store: "cookie_store",
      path: "/users/sign_in",
      request_method: "POST",
      approximate_session_bytes: 128,
      session_key_count: 4
    )
    expect(event[:recorded_at]).to be_present
  end
end
