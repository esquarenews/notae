require "rails_helper"

RSpec.describe "Notae AI settings", type: :request do
  it "renders the loader preview and style library" do
    user = User.create!(email: "notae-ai-settings-owner@example.com", password: "password123", ai_loader_style: "neon_mesh")
    workspace = Workspace.create!(name: "Notae AI settings", slug: "notae-ai-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_notae_ai_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notae AI loader")
    expect(response.body).to include("Static state")
    expect(response.body).to include("Loading state")
    expect(response.body).to include("Style library")
    expect(response.body).to include("Disco Orbit")
    expect(response.body).to include("Neural Network")
    expect(response.body).to include("Luminous Pulse Sphere")
    expect(response.body).to include("Luminous Wave Sphere")
    expect(response.body).to include("notae-ai-loader")
    expect(response.body).to include("p-24")
    expect(response.body).to include("notae-ai-loader-options-grid is-two-column")
    expect(response.body).to include("notae-settings-nav-item active")
  end

  it "updates the selected Notae AI loader style for the current user" do
    user = User.create!(email: "notae-ai-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Notae AI settings update", slug: "notae-ai-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_notae_ai_settings_path(workspace_slug: workspace.slug),
          params: { user: { ai_loader_style: "neural_network" } }

    expect(response).to redirect_to(workspace_notae_ai_settings_path(workspace_slug: workspace.slug))
    expect(user.reload.ai_loader_style).to eq("neural_network")
  end
end
