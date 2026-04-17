require "rails_helper"

RSpec.describe "API V1 Workspaces", type: :request do
  def json_body
    JSON.parse(response.body)
  end

  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  it "lists only accessible workspaces and includes the caller role" do
    user = User.create!(email: "api-workspaces-user@example.com", password: "password123")
    other_user = User.create!(email: "api-workspaces-other@example.com", password: "password123")
    alpha = Workspace.create!(name: "Alpha Space", slug: "alpha-space")
    beta = Workspace.create!(name: "Beta Space", slug: "beta-space")
    hidden = Workspace.create!(name: "Hidden Space", slug: "hidden-space")
    Membership.create!(workspace: alpha, user: user, role: :owner)
    Membership.create!(workspace: beta, user: user, role: :member)
    Membership.create!(workspace: hidden, user: other_user, role: :owner)
    token = ApiToken.create!(user: user, name: "Workspace index token")

    get "/api/v1/workspaces", params: { q: "space" }, headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    payload = json_body.fetch("data")

    expect(payload.map { |entry| entry.fetch("slug") }).to contain_exactly(alpha.slug, beta.slug)
    expect(payload.find { |entry| entry.fetch("slug") == alpha.slug }.fetch("role")).to eq("owner")
    expect(payload.find { |entry| entry.fetch("slug") == beta.slug }.fetch("role")).to eq("member")
  end
end
