require "rails_helper"

RSpec.describe "Connection settings", type: :request do
  def stub_rails_env(name)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(name))
  end

  it "renders connection settings without user-managed secret controls" do
    user = User.create!(email: "connection-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings", slug: "connection-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_connection_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Managed connections")
    expect(response.body).to include("External service credentials are managed through the application environment.")
    expect(response.body).not_to include("OpenAI API key")
    expect(response.body).not_to include("Save key")
    expect(response.body).not_to include("Remove key")
    expect(response.body).not_to include("Email SMTP credentials")
    expect(response.body).not_to include("Save SMTP")
    expect(response.body).not_to include("Remove SMTP")
    expect(response.body).to include("notae-settings-nav-icon")
  end

  it "renders OpenAI key controls in development" do
    stub_rails_env("development")
    user = User.create!(email: "connection-settings-dev-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings dev", slug: "connection-settings-dev")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_connection_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("OpenAI API key")
    expect(response.body).to include("Save key")
    expect(response.body).to include("Remove key")
    expect(response.body).to include("Add your OpenAI API key for AI-powered actions in development.")
  end

  it "ignores legacy OpenAI key posts because secrets are environment-managed" do
    user = User.create!(email: "connection-settings-update@example.com", password: "password123", openai_api_key: "sk-existing")
    workspace = Workspace.create!(name: "Connection settings update", slug: "connection-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-abc123" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to eq("sk-existing")

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { clear_openai_api_key: "1" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to eq("sk-existing")
  end

  it "updates and clears the OpenAI API key in development" do
    stub_rails_env("development")
    user = User.create!(email: "connection-settings-dev-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings dev update", slug: "connection-settings-dev-update")
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

  it "ignores legacy SMTP settings posted to connection settings" do
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
    expect(user.smtp_address).to be_nil
    expect(user.smtp_port).to be_nil
    expect(user.smtp_domain).to be_nil
    expect(user.smtp_username).to be_nil
    expect(user.smtp_password).to be_nil
    expect(user.smtp_authentication).to eq("plain")
    expect(user.smtp_enable_starttls_auto).to be(true)
    expect(user.smtp_from_name).to be_nil
    expect(user.smtp_from_email).to be_nil
  end

  it "does not clear legacy SMTP settings from connection settings" do
    user = User.create!(
      email: "connection-settings-smtp-clear@example.com",
      password: "password123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_email: "noreply@example.com"
    )
    workspace = Workspace.create!(name: "Connection settings smtp clear", slug: "connection-settings-smtp-clear")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { clear_smtp_settings: "1" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    user.reload
    expect(user.smtp_address).to eq("smtp.example.com")
    expect(user.smtp_port).to eq(587)
    expect(user.smtp_username).to eq("smtp-user")
    expect(user.smtp_password).to eq("smtp-password-123")
    expect(user.smtp_from_email).to eq("noreply@example.com")
    expect(user.smtp_authentication).to eq("plain")
    expect(user.smtp_enable_starttls_auto).to be(true)
  end

  it "returns turbo stream updates for environment-managed connection settings" do
    user = User.create!(email: "connection-settings-turbo@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings turbo", slug: "connection-settings-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-turbo-123" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include('turbo-stream action="replace" target="connection_settings_content"')
    expect(response.body).to include("Connection settings are managed by the application environment.")
    expect(user.reload.openai_api_key).to be_nil
  end

  it "returns turbo stream updates for development OpenAI key saves" do
    stub_rails_env("development")
    user = User.create!(email: "connection-settings-dev-turbo@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings dev turbo", slug: "connection-settings-dev-turbo")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-turbo-123" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include('turbo-stream action="replace" target="settings_flash_messages"')
    expect(response.body).to include('turbo-stream action="replace" target="connection_settings_content"')
    expect(response.body).to include("OpenAI API key saved.")
    expect(user.reload.openai_api_key).to eq("sk-test-turbo-123")
  end

  it "does not require encryption config for ignored legacy connection secret posts" do
    user = User.create!(email: "connection-settings-bootstrap@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings bootstrap", slug: "connection-settings-bootstrap")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    runtime_config = ActiveRecord::Encryption.config
    app_config = Rails.application.config.active_record.encryption
    original_values = {
      runtime_primary: runtime_config.instance_variable_get(:@primary_key),
      runtime_deterministic: runtime_config.instance_variable_get(:@deterministic_key),
      runtime_salt: runtime_config.instance_variable_get(:@key_derivation_salt),
      app_primary: app_config.instance_variable_get(:@primary_key),
      app_deterministic: app_config.instance_variable_get(:@deterministic_key),
      app_salt: app_config.instance_variable_get(:@key_derivation_salt)
    }

    runtime_config.instance_variable_set(:@primary_key, nil)
    runtime_config.instance_variable_set(:@deterministic_key, nil)
    runtime_config.instance_variable_set(:@key_derivation_salt, nil)
    app_config.instance_variable_set(:@primary_key, nil)
    app_config.instance_variable_set(:@deterministic_key, nil)
    app_config.instance_variable_set(:@key_derivation_salt, nil)

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-bootstrap-123" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to be_nil
  ensure
    runtime_config.instance_variable_set(:@primary_key, original_values[:runtime_primary]) if runtime_config
    runtime_config.instance_variable_set(:@deterministic_key, original_values[:runtime_deterministic]) if runtime_config
    runtime_config.instance_variable_set(:@key_derivation_salt, original_values[:runtime_salt]) if runtime_config
    app_config.instance_variable_set(:@primary_key, original_values[:app_primary]) if app_config
    app_config.instance_variable_set(:@deterministic_key, original_values[:app_deterministic]) if app_config
    app_config.instance_variable_set(:@key_derivation_salt, original_values[:app_salt]) if app_config
  end

  it "recovers missing encryption config before saving development connection secrets" do
    stub_rails_env("development")
    user = User.create!(email: "connection-settings-dev-bootstrap@example.com", password: "password123")
    workspace = Workspace.create!(name: "Connection settings dev bootstrap", slug: "connection-settings-dev-bootstrap")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    runtime_config = ActiveRecord::Encryption.config
    app_config = Rails.application.config.active_record.encryption
    original_values = {
      runtime_primary: runtime_config.instance_variable_get(:@primary_key),
      runtime_deterministic: runtime_config.instance_variable_get(:@deterministic_key),
      runtime_salt: runtime_config.instance_variable_get(:@key_derivation_salt),
      app_primary: app_config.instance_variable_get(:@primary_key),
      app_deterministic: app_config.instance_variable_get(:@deterministic_key),
      app_salt: app_config.instance_variable_get(:@key_derivation_salt)
    }

    runtime_config.instance_variable_set(:@primary_key, nil)
    runtime_config.instance_variable_set(:@deterministic_key, nil)
    runtime_config.instance_variable_set(:@key_derivation_salt, nil)
    app_config.instance_variable_set(:@primary_key, nil)
    app_config.instance_variable_set(:@deterministic_key, nil)
    app_config.instance_variable_set(:@key_derivation_salt, nil)

    patch workspace_connection_settings_path(workspace_slug: workspace.slug),
          params: { user: { openai_api_key: "sk-test-bootstrap-123" } }

    expect(response).to redirect_to(workspace_connection_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.openai_api_key).to eq("sk-test-bootstrap-123")
    expect(runtime_config.instance_variable_get(:@primary_key)).to be_present
    expect(runtime_config.instance_variable_get(:@deterministic_key)).to be_present
    expect(runtime_config.instance_variable_get(:@key_derivation_salt)).to be_present
  ensure
    runtime_config.instance_variable_set(:@primary_key, original_values[:runtime_primary]) if runtime_config
    runtime_config.instance_variable_set(:@deterministic_key, original_values[:runtime_deterministic]) if runtime_config
    runtime_config.instance_variable_set(:@key_derivation_salt, original_values[:runtime_salt]) if runtime_config
    app_config.instance_variable_set(:@primary_key, original_values[:app_primary]) if app_config
    app_config.instance_variable_set(:@deterministic_key, original_values[:app_deterministic]) if app_config
    app_config.instance_variable_set(:@key_derivation_salt, original_values[:app_salt]) if app_config
  end
end
