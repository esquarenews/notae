require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  it "lets an authenticated user create a workspace and become owner" do
    user = User.create!(email: "owner@example.com", password: "password123")
    sign_in user

    expect do
      post workspaces_path, params: { workspace: { name: "Product", slug: "product-team" } }
    end.to change(Workspace, :count).by(1)

    workspace = Workspace.find_by!(slug: "product-team")

    expect(response).to redirect_to(workspace_path("product-team"))
    expect(Membership.find_by!(workspace: workspace, user: user).role).to eq("owner")
  end

  it "restricts workspace access to members" do
    owner = User.create!(email: "ws-owner@example.com", password: "password123")
    outsider = User.create!(email: "outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Engineering", slug: "engineering")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in outsider
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:not_found)
  end
end
