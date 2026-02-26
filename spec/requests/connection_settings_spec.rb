require "rails_helper"

RSpec.describe "Connection settings", type: :request do
  it "renders connections settings with OpenAI key controls and nav icons" do
    user = User.create!(email: "connection-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings", slug: "connection-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_connection_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OpenAI API key")
    expect(response.body).to include("Save key")
    expect(response.body).to include("Remove key")
    expect(response.body).to include("Email SMTP credentials")
    expect(response.body).to include("Save SMTP")
    expect(response.body).to include("Remove SMTP")
    expect(response.body).to include("notae-settings-nav-icon")
  end

  it "updates and clears the OpenAI API key for current user" do
    user = User.create!(email: "connection-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings update", slug: "connection-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-abc123" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to eq("sk-test-abc123")

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { clear_openai_api_key: "1" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to be_nil
  end

  it "updates and clears SMTP settings for current user" do
    user = User.create!(email: "connection-settings-smtp@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings smtp", slug: "connection-settings-smtp")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: {
            user: {
              smtp_address: "smtp.example.com",
              smtp_port: "587",
              smtp_domain: "example.com",
              smtp_username: "smtp-user",
              smtp_password: "smtp-password-123",
              smtp_authentication: "login",
              smtp_enable_starttls_auto: "1",
              smtp_from_name: "Notae Team",
              smtp_from_email: "noreply@example.com"
            }
          }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    user.reload
    expect(user.smtp_address).to eq("smtp.example.com")
    expect(user.smtp_port).to eq(587)
    expect(user.smtp_domain).to eq("example.com")
    expect(user.smtp_username).to eq("smtp-user")
    expect(user.smtp_password).to eq("smtp-password-123")
    expect(user.smtp_authentication).to eq("login")
    expect(user.smtp_enable_starttls_auto).to be(true)
    expect(user.smtp_from_name).to eq("Notae Team")
    expect(user.smtp_from_email).to eq("noreply@example.com")

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { clear_smtp_settings: "1" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    user.reload
    expect(user.smtp_address).to be_nil
    expect(user.smtp_port).to be_nil
    expect(user.smtp_domain).to be_nil
    expect(user.smtp_username).to be_nil
    expect(user.smtp_password).to be_nil
    expect(user.smtp_from_name).to be_nil
    expect(user.smtp_from_email).to be_nil
    expect(user.smtp_authentication).to eq("plain")
    expect(user.smtp_enable_starttls_auto).to be(true)
  end
end
