require "rails_helper"

RSpec.describe "Settings auto-submit CSP safety", type: :request do
  it "uses Stimulus actions instead of inline onchange handlers across settings pages" do
    user = User.create!(email: "settings-csp@example.com", password: "password123")
    workspace = Workspace.create!(name: "Settings CSP", slug: "settings-csp")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    paths = [
      workspace_preferences_path(workspace_slug: workspace.slug),
      workspace_notification_settings_path(workspace_slug: workspace.slug),
      workspace_general_settings_path(workspace_slug: workspace.slug),
      workspace_people_settings_path(workspace_slug: workspace.slug),
      workspace_notae_ai_settings_path(workspace_slug: workspace.slug),
      workspace_kalendarium_settings_path(workspace_slug: workspace.slug)
    ]

    paths.each do |path|
      get path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("onchange=")
      expect(response.body).to include("auto-submit")
    end
  end
end
