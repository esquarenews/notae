require "rails_helper"

RSpec.describe "Home styling", type: :request do
  it "renders the signed-in home page with branded card layout" do
    user = User.create!(email: "home-styling-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Styled Home", slug: "styled-home")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("notae-home-page")
    expect(response.body).to include("notae-home-card")
    expect(response.body).to include("notae-home-workspace-item")
    expect(response.body).to include("/icon-light-v5.svg")
    expect(response.body).to include("Styled Home")
  end
end
