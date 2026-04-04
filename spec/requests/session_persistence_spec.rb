require "rails_helper"

RSpec.describe "Session persistence", type: :request do
  it "sets a persistent first-party session cookie on sign in" do
    user = User.create!(email: "persistent-session@example.com", password: "password123")

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123",
        remember_me: "0"
      }
    }

    expect(response).to have_http_status(:redirect)

    cookie_header = response.headers["Set-Cookie"].to_s

    expect(cookie_header).to include("_notae_session=")
    expect(cookie_header).to match(/expires=/i)
    expect(cookie_header).to match(/samesite=lax/i)
  end

  it "configures the cookie store with a persistent expiry for standalone relaunches" do
    options = Rails.application.config.session_options

    expect(options[:key]).to eq("_notae_session")
    expect(options[:expire_after]).to eq(30.days)
    expect(options[:same_site]).to eq(:lax)
    expect(options[:httponly]).to be(true)
  end
end
