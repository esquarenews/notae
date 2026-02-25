require "rails_helper"

RSpec.describe "Authentication branding", type: :request do
  it "renders a branded login page with icon and streamlined form" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae")
    expect(response.body).to include("Sign in")
    expect(response.body).to include("notae-auth-brand-icon")
    expect(response.body).to include("/icon.svg")
    expect(response.body).to include("notae-auth-card")
  end
end
