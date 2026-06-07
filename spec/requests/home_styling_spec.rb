require "rails_helper"

RSpec.describe "Home styling", type: :request do
  it "redirects signed-in users from root to their workspace" do
    user = User.create!(email: "home-styling-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Styled Home", slug: "styled-home")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get root_path

    expect(response).to redirect_to(workspace_path(workspace.slug))
  end
end
