require "rails_helper"

RSpec.describe "Preferences", type: :request do
  it "renders the account preferences menu with future markers" do
    user = User.create!(email: "preferences-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Prefs", slug: "prefs")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_preferences_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preferences")
    expect(response.body).to include("Appearance")
    expect(response.body).to include("Language & Time")
    expect(response.body).to include("Desktop app")
    expect(response.body).to include("Privacy")
    expect(response.body).to include("Reduce Notae AI loader motion")
    expect(response.body).to include("Future implementation")
    expect(response.body).to include("notae-settings-mobile-accordion")
    expect(response.body).to include("notae-settings-mobile-trigger")
    expect(response.body).to include("notae-settings-nav-body")
  end

  it "updates preference values for the signed-in user" do
    user = User.create!(email: "preferences-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Prefs update", slug: "prefs-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_preferences_path(workspace_slug: workspace.slug),
          params: {
            user: {
              theme_preference: "dark",
              language_preference: "en-GB",
              show_text_direction_controls: "1",
              start_week_preference: "sunday",
              date_format_preference: "full_date",
              auto_time_zone: "0",
              time_zone: "UTC",
              open_links_in_desktop_app: "0",
              open_on_start_preference: "workspace_home",
              reduce_ai_loader_motion: "1",
              cookie_settings_preference: "strict",
              show_view_history: "0",
              profile_discoverability: "0"
            }
          }

    expect(response).to redirect_to(workspace_preferences_path(workspace_slug: workspace.slug))

    user.reload
    expect(user.theme_preference).to eq("dark")
    expect(user.language_preference).to eq("en-GB")
    expect(user.show_text_direction_controls).to be(true)
    expect(user.start_week_on_monday).to be(false)
    expect(user.date_format_preference).to eq("full_date")
    expect(user.auto_time_zone).to be(false)
    expect(user.time_zone).to eq("UTC")
    expect(user.open_links_in_desktop_app).to be(false)
    expect(user.open_on_start_preference).to eq("workspace_home")
    expect(user.reduce_ai_loader_motion).to be(true)
    expect(user.cookie_settings_preference).to eq("strict")
    expect(user.show_view_history).to be(false)
    expect(user.profile_discoverability).to be(false)
  end

  it "still updates preferences when legacy SMTP settings are incomplete" do
    user = User.create!(email: "preferences-smtp-legacy@example.com", password: "password123")
    user.update_columns(
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_username: "mailer@example.com",
      smtp_from_email: "mailer@example.com"
    )
    workspace = Workspace.create!(name: "Prefs smtp legacy", slug: "prefs-smtp-legacy")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_preferences_path(workspace_slug: workspace.slug),
          params: { user: { theme_preference: "dark" } }

    expect(response).to redirect_to(workspace_preferences_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to be_blank
    expect(user.reload.theme_preference).to eq("dark")
  end

  it "rejects unsupported time zones" do
    user = User.create!(email: "preferences-invalid-timezone@example.com", password: "password123")
    workspace = Workspace.create!(name: "Prefs invalid timezone", slug: "prefs-invalid-timezone")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_preferences_path(workspace_slug: workspace.slug),
          params: { user: { auto_time_zone: "0", time_zone: "Mars/Olympus" } }

    expect(response).to redirect_to(workspace_preferences_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("Time zone is not supported")
    expect(user.reload.time_zone).to eq("UTC")
  end

  it "applies the selected theme class in the app layout" do
    user = User.create!(
      email: "preferences-theme@example.com",
      password: "password123",
      theme_preference: "dark"
    )
    workspace = Workspace.create!(name: "Prefs theme", slug: "prefs-theme")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_preferences_path(workspace_slug: workspace.slug)

    expect(response.body).to include("notae-theme-dark")
  end

  it "supports system theme mode" do
    user = User.create!(email: "preferences-theme-system@example.com", password: "password123")
    workspace = Workspace.create!(name: "Prefs theme system", slug: "prefs-theme-system")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_preferences_path(workspace_slug: workspace.slug),
          params: { user: { theme_preference: "system" } }
    expect(response).to redirect_to(workspace_preferences_path(workspace_slug: workspace.slug))
    expect(user.reload.theme_preference).to eq("system")

    get workspace_preferences_path(workspace_slug: workspace.slug)
    expect(response.body).to include("notae-theme-system")
  end

  it "renders preferences when another workspace has a blank slug" do
    user = User.create!(email: "preferences-blank-slug@example.com", password: "password123")
    workspace = Workspace.create!(name: "Prefs stable", slug: "prefs-stable")
    stale_workspace = Workspace.create!(name: "Prefs stale", slug: "prefs-stale")
    stale_workspace.update_column(:slug, "")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: stale_workspace, user: user, role: :owner)
    sign_in user

    get workspace_preferences_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preferences")
  end
end
