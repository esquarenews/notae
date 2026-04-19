require "rails_helper"

RSpec.describe Users::SessionsController, type: :controller do
  include Devise::Test::ControllerHelpers

  before do
    @request.env["devise.mapping"] = Devise.mappings[:user]
  end

  describe "POST #create" do
    it "redirects to the last workspace after sign in when no stored location exists" do
      user = User.create!(email: "auth-last-workspace@example.com", password: "password123")
      first_workspace = Workspace.create!(name: "First workspace", slug: "auth-first-workspace")
      last_workspace = Workspace.create!(name: "Last workspace", slug: "auth-last-workspace")
      Membership.create!(workspace: first_workspace, user: user, role: :owner)
      Membership.create!(workspace: last_workspace, user: user, role: :owner)

      session["notae_last_workspace_slug"] = last_workspace.slug

      post :create, params: {
        user: {
          email: user.email,
          password: "password123",
          remember_me: "1"
        }
      }

      expect(response).to redirect_to(workspace_path(last_workspace.slug))
    end

    it "prefers the stored location over the last workspace on sign in" do
      user = User.create!(email: "auth-stored-location@example.com", password: "password123")
      workspace = Workspace.create!(name: "Stored location workspace", slug: "auth-stored-location")
      last_workspace = Workspace.create!(name: "Other workspace", slug: "auth-other-workspace")
      Membership.create!(workspace: workspace, user: user, role: :owner)
      Membership.create!(workspace: last_workspace, user: user, role: :owner)

      session["notae_last_workspace_slug"] = last_workspace.slug
      session["user_return_to"] = workspace_notification_settings_path(workspace_slug: workspace.slug)

      post :create, params: {
        user: {
          email: user.email,
          password: "password123",
          remember_me: "1"
        }
      }

      expect(response).to redirect_to(workspace_notification_settings_path(workspace_slug: workspace.slug))
    end
  end
end
