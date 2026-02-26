require "rails_helper"

RSpec.describe "General settings", type: :request do
  it "renders workspace controls in general settings" do
    user = User.create!(email: "general-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "General settings", slug: "general-settings")
    other_workspace = Workspace.create!(name: "General settings alt", slug: "general-settings-alt")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    Membership.create!(workspace: other_workspace, user: user, role: :owner)
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

    document = Nokogiri::HTML(response.body)
    workspace_picker = document.at_css(".notae-settings-workspace-picker select[name='workspace_nav_picker']")
    expect(workspace_picker).to be_present
    expect(workspace_picker["onchange"]).to eq("window.location.href=this.value")
    picker_options = workspace_picker.css("option").map { |option| [ option.text.strip, option["value"] ] }
    expect(picker_options).to include(
      [ workspace.name, workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug) ],
      [ other_workspace.name, workspace_general_settings_path(workspace_slug: other_workspace.slug, settings_workspace_slug: other_workspace.slug) ]
    )
    selected_option = workspace_picker.css("option").find { |option| option["selected"].present? }
    expect(selected_option&.[]("value")).to eq(workspace_general_settings_path(workspace_slug: workspace.slug, settings_workspace_slug: workspace.slug))
  end

  it "renders workspace name and icon for the selected workspace context" do
    user = User.create!(email: "general-settings-context@example.com", password: "password123")
    primary_workspace = Workspace.create!(name: "Primary Workspace", slug: "general-settings-context-primary", icon: Workspace::DISCO_ICON_OPTIONS.first)
    selected_workspace = Workspace.create!(name: "Selected Workspace", slug: "general-settings-context-selected", icon: Workspace::DISCO_ICON_OPTIONS.second)
    Membership.create!(workspace: primary_workspace, user: user, role: :owner)
    Membership.create!(workspace: selected_workspace, user: user, role: :owner)
    sign_in user

    get workspace_general_settings_path(workspace_slug: selected_workspace.slug, settings_workspace_slug: selected_workspace.slug)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    name_input = document.at_css(".notae-general-name-input")
    expect(name_input&.[]("value")).to eq("Selected Workspace")
    active_icon = document.at_css(".notae-general-icon-option.is-active .notae-general-icon-glyph")
    expect(active_icon&.text&.strip).to eq(Workspace::DISCO_ICON_OPTIONS.second)
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
