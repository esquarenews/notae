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
end
