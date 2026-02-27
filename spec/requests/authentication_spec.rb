require "rails_helper"

RSpec.describe "Authentication", type: :request do
  before do
    ActionMailer::Base.deliveries.clear
  end

  it "renders the devise login page" do
    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in")
  end

  it "allows sign up, login, and logout" do
    post user_registration_path, params: {
      user: {
        email: "new-user@example.com",
        password: "password123",
        password_confirmation: "password123"
      }
    }

    expect(response).to redirect_to(root_path)

    delete destroy_user_session_path
    expect(response).to redirect_to(root_path)

    post user_session_path, params: {
      user: {
        email: "new-user@example.com",
        password: "password123"
      }
    }

    expect(response).to redirect_to(root_path)
  end

  it "re-renders sign up with validation errors instead of redirecting on invalid registration" do
    post user_registration_path, params: {
      user: {
        email: "invalid-email",
        password: "short",
        password_confirmation: "mismatch"
      }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Create account")
    expect(response.body).to include("notae-auth-form")
    expect(response.body).to include("Password confirmation")
  end

  it "redirects invalid login attempts back to sign in with an alert" do
    post user_session_path, params: {
      user: {
        email: "missing-user@example.com",
        password: "wrong-password"
      }
    }

    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to include("Invalid")
  end

  it "persists session across requests after login" do
    user = User.create!(email: "persist@example.com", password: "password123")

    post user_session_path, params: { user: { email: user.email, password: "password123" } }
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Welcome back, #{user.email}.")
  end

  it "sends password reset instructions" do
    user = User.create!(email: "reset@example.com", password: "password123")

    post user_password_path, params: { user: { email: user.email } }

    expect(response).to redirect_to(new_user_session_path)
    expect(ActionMailer::Base.deliveries.last.to).to include(user.email)
  end

  it "redirects to sign in when CSRF token is invalid" do
    previous_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      post user_session_path,
           params: {
             authenticity_token: "invalid",
             user: { email: "nobody@example.com", password: "password123" }
           }
    ensure
      ActionController::Base.allow_forgery_protection = previous_setting
    end

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("Your session expired. Please sign in again.")
  end
end
