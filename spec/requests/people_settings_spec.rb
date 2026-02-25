require "rails_helper"

RSpec.describe "People settings", type: :request do
  it "renders people settings with invite link controls and tabs" do
    owner = User.create!(email: "people-settings-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "People settings", slug: "people-settings")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    sign_in owner

    get workspace_people_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Add members via link")
    expect(response.body).to include("Copy link")
    expect(response.body).to include("Guests")
    expect(response.body).to include("Members")
  end

  it "updates add-members-by-link toggle and can regenerate the link token" do
    owner = User.create!(email: "people-settings-toggle@example.com", password: "password123")
    workspace = Workspace.create!(name: "People settings toggle", slug: "people-settings-toggle")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.ensure_join_link_token!
    previous_token = workspace.join_link_token
    sign_in owner

    patch workspace_people_settings_path(workspace_slug: workspace.slug),
          params: { workspace: { join_link_enabled: "1" } }
    expect(response).to redirect_to(workspace_people_settings_path(workspace_slug: workspace.slug))
    expect(workspace.reload.join_link_enabled).to be(true)

    patch workspace_people_settings_path(workspace_slug: workspace.slug),
          params: { workspace: { regenerate_join_link: "1" } }
    expect(response).to redirect_to(workspace_people_settings_path(workspace_slug: workspace.slug))
    expect(workspace.reload.join_link_token).not_to eq(previous_token)
  end

  it "allows a signed-in user to join a workspace with a valid join token" do
    owner = User.create!(email: "people-settings-link-owner@example.com", password: "password123")
    guest = User.create!(email: "people-settings-link-guest@example.com", password: "password123")
    workspace = Workspace.create!(name: "People settings link", slug: "people-settings-link")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.ensure_join_link_token!
    workspace.update!(join_link_enabled: true)
    sign_in guest

    expect do
      get workspace_join_link_path(workspace_slug: workspace.slug, token: workspace.join_link_token)
    end.to change(Membership, :count).by(1)

    expect(response).to redirect_to(workspace_path(workspace.slug))
    expect(Membership.find_by!(workspace: workspace, user: guest).role).to eq("member")
  end
end
