require "rails_helper"

RSpec.describe "Authentication branding", type: :request do
  it "keeps the auth submit button label high contrast on the accent button" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-theme .notae-auth-submit,\n.notae-theme a.notae-auth-submit,\n.notae-theme button.notae-auth-submit,\n.notae-theme input[type=\"submit\"].notae-auth-submit {\n  color: #f8fbfc;\n  text-shadow: 0 1px 1px rgba(15, 23, 42, 0.22);")
    expect(stylesheet).to include(".notae-theme .notae-auth-submit:hover,\n.notae-theme .notae-auth-submit:focus-visible,\n.notae-theme a.notae-auth-submit:hover,\n.notae-theme a.notae-auth-submit:focus-visible {\n  color: #ffffff;\n}")
    expect(stylesheet).to include(".notae-onboarding-progress {")
    expect(stylesheet).to include(".notae-auth-submit-progress {")
    expect(stylesheet).to include("@keyframes notae-auth-submit-spin")
  end

  it "renders a branded login page with icon and streamlined form" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae")
    expect(response.body).to include("Sign in")
    expect(response.body).to include("notae-auth-brand-icon")
    expect(response.body).to include("/icon-light-v5.svg")
    expect(response.body).to include("notae-auth-card")
    expect(response.body).to include('data-turbo="false"')
  end

  it "renders auth flow flash messages in the dedicated auth flash host" do
    User.create!(email: "auth-flash-host@example.com", password: "password123")

    post user_session_path,
         params: { user: { email: "auth-flash-host@example.com", password: "wrong-password" } }

    expect(response).to have_http_status(:see_other)
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-auth-flash-host")
    expect(response.body).to include("Invalid email or password.")
  end

  it "renders a branded sign up page with the shared auth shell classes" do
    get new_user_registration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create account")
    expect(response.body).to include("notae-auth-page")
    expect(response.body).to include("notae-auth-brand-icon")
    expect(response.body).to include("notae-auth-form")
    expect(response.body).to include("notae-auth-input")
    expect(response.body).to include("notae-auth-submit")
    expect(response.body).to include("notae-onboarding-progress")
    expect(response.body).to include("Account")
    expect(response.body).to include("Email confirmation")
    expect(response.body).to include("Workspace & trial")
    expect(response.body).to include("Creating your account and preparing the next onboarding step.")
    expect(response.body).to include("notae-auth-submit-progress")
    expect(response.body).to include("data-controller=\"auth-submit\"")
    expect(response.body).to include('data-turbo="false"')
  end

  it "renders a branded forgot password page with the shared auth shell classes" do
    get new_user_password_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Forgot your password?")
    expect(response.body).to include("notae-auth-page")
    expect(response.body).to include("notae-auth-brand-icon")
    expect(response.body).to include("notae-auth-form")
    expect(response.body).to include("notae-auth-input")
    expect(response.body).to include("notae-auth-submit")
    expect(response.body).to include('data-turbo="false"')
  end
end
