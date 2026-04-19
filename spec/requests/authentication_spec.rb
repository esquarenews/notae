require "rails_helper"

RSpec.describe "Authentication", type: :request do
  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  it "signs in a valid user through the Devise session form" do
    user = User.create!(email: "auth-request@example.com", password: "password123")

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123",
        remember_me: "0"
      }
    }

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Signed in successfully.")
    expect(response.body).to include(user.email)
  end

  it "rejects an invalid password through the Devise session form" do
    user = User.create!(email: "auth-request-invalid@example.com", password: "password123")

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "wrong-password",
        remember_me: "0"
      }
    }

    expect(response).to redirect_to(new_user_session_path)
    follow_redirect!
    expect(response.body).to include("Invalid email or password.")
  end

  it "queues password reset instructions for an existing user" do
    user = User.create!(email: "auth-reset@example.com", password: "password123")

    post user_password_path, params: {
      user: {
        email: user.email
      }
    }

    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.reset_password_token).to be_present
    follow_redirect!
    expect(response.body).to include("If your email address exists in our database")
  end

  it "renders the reset password edit form with the shared auth styling" do
    user = User.create!(email: "auth-reset-edit@example.com", password: "password123")
    raw_token, encrypted_token = Devise.token_generator.generate(User, :reset_password_token)
    user.update_columns(
      reset_password_token: encrypted_token,
      reset_password_sent_at: Time.current,
      updated_at: Time.current
    )

    get edit_user_password_path(reset_password_token: raw_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Change your password")
    expect(response.body).to include("Choose a new password for your account.")
    expect(response.body).to include("notae-auth-card")
    expect(response.body).to include("notae-auth-input")
    expect(response.body).not_to include("devise/shared/_links")
  end

  it "records sign-in and sign-out diagnostics for the user" do
    user = User.create!(email: "auth-diagnostics@example.com", password: "password123")

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123",
        remember_me: "1"
      }
    }

    delete destroy_user_session_path

    reasons = Notae::SessionEventStore.fetch(user_id: user.id).map { |event| event[:reason] }

    expect(reasons).to include("signed_in", "signed_out")
  end

end
