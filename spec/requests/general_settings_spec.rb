require "rails_helper"

RSpec.describe "General settings", type: :request do
  it "renders workspace controls in general settings" do
    user = User.create!(email: "general-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "General settings", slug: "general-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Workspace settings")
    expect(response.body).to include("Workspace name")
    expect(response.body).to include("Save and display page view analytics")
    expect(response.body).to include("Delete workspace")
    expect(response.body).to include("Workspace ID")
    expect(response.body).to include(workspace.id)
    expect(response.body).to include("notae-general-icon-option")
    expect(response.body).to include("Final confirmation")
  end

  it "updates workspace name, icon, and analytics settings" do
    user = User.create!(email: "general-settings-update@example.com", password: "password123")
    workspace = Workspace.create!(name: "Original workspace", slug: "general-settings-update")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    patch workspace_general_settings_path(workspace_slug: workspace.slug),
          params: {
            workspace: {
              name: "Disco HQ",
              icon: Workspace::DISCO_ICON_OPTIONS.first,
              analytics_enabled: "0"
            }
          }

    expect(response).to redirect_to(workspace_general_settings_path(workspace_slug: workspace.slug))

    workspace.reload
    expect(workspace.name).to eq("Disco HQ")
    expect(workspace.icon).to eq(Workspace::DISCO_ICON_OPTIONS.first)
    expect(workspace.analytics_enabled).to be(false)
  end

  it "requires exact name to archive workspace" do
    user = User.create!(email: "general-settings-delete-name-check@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete check", slug: "general-settings-delete-name-check")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    delete workspace_general_settings_path(workspace_slug: workspace.slug),
           params: { workspace: { confirm_name: "wrong name" } }

    expect(response).to redirect_to(workspace_general_settings_path(workspace_slug: workspace.slug))
    expect(workspace.reload.archived_at).to be_nil
  end

  it "allows owners to archive the workspace from danger zone" do
    user = User.create!(email: "general-settings-delete-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Delete me", slug: "general-settings-delete-owner")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    delete workspace_general_settings_path(workspace_slug: workspace.slug),
           params: { workspace: { confirm_name: workspace.name } }

    expect(response).to redirect_to(root_path)
    expect(workspace.reload.archived_at).to be_present
  end
end
