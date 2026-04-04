require "rails_helper"

RSpec.describe "Favicon settings", type: :request do
  it "renders favicon lab with candidate previews and tab-preview controls" do
    user = User.create!(email: "favicon-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favicon Workspace", slug: "favicon-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_favicon_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Favicon Lab")
    expect(response.body).to include("Candidate set for stronger browser-tab visibility")
    expect(response.body).to include("Restore current favicon")
    expect(response.body).to include("Preview in tab")
    expect(response.body).to include("/favicons/candidates/disco-core.svg")
    expect(response.body).to include("/favicons/candidates/neon-n.svg")
    expect(response.body).to include("data-controller=\"favicon-preview\"")
    expect(response.body).to include("data-favicon-preview-default-href-value=\"/icon-v3.svg\"")
    expect(response.body).to include("notae-settings-nav-item is-disabled active")
    expect(response.body).to include("Internal")
  end

  it "redirects placeholder workspace slugs to a valid workspace favicon settings page" do
    user = User.create!(email: "favicon-settings-placeholder@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favicon Placeholder", slug: "favicon-placeholder")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_favicon_settings_path(workspace_slug: ":workspace_slug")

    expect(response).to redirect_to(workspace_favicon_settings_path(workspace_slug: workspace.slug))
    expect(flash[:alert]).to include("Select a valid workspace")
  end
end
