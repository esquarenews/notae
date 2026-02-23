require "rails_helper"

RSpec.describe "Home", type: :request do
  it "renders the root page with the base layout" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<title>Notae</title>")
    expect(response.body).to include("Sign in")
  end

  it "shows only policy-scoped workspaces for an authenticated user" do
    user = User.create!(email: "member@example.com", password: "password123")
    other_user = User.create!(email: "other@example.com", password: "password123")
    visible_workspace = Workspace.create!(name: "Visible", slug: "visible")
    hidden_workspace = Workspace.create!(name: "Hidden", slug: "hidden")

    Membership.create!(user: user, workspace: visible_workspace, role: :owner)
    Membership.create!(user: other_user, workspace: hidden_workspace, role: :owner)

    sign_in user
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visible")
    expect(response.body).not_to include("Hidden")
    expect(response.body).to include("New Workspace")
  end
end
