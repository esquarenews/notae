require "rails_helper"

RSpec.describe "Authentication branding", type: :request do
  it "keeps the auth submit button label high contrast on the accent button" do
    stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read

    expect(stylesheet).to include(".notae-auth-submit,\na.notae-auth-submit,\nbutton.notae-auth-submit,\ninput[type=\"submit\"].notae-auth-submit {\n  color: #f8fbfc;\n  text-shadow: 0 1px 1px rgba(15, 23, 42, 0.22);")
    expect(stylesheet).to include(".notae-auth-submit:hover,\n.notae-auth-submit:focus-visible {\n  color: #ffffff;\n}")
  end

  it "renders a branded login page with icon and streamlined form" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae")
    expect(response.body).to include("Sign in")
    expect(response.body).to include("notae-auth-brand-icon")
    expect(response.body).to include("/icon-v3.svg")
    expect(response.body).to include("notae-auth-card")
    expect(response.body).to include('data-turbo="false"')
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
