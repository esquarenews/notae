require "rails_helper"

RSpec.describe "API V1 Rate Limiting", type: :request do
  def auth_headers(token)
    { "Authorization" => "Bearer #{token.token}", "Accept" => "application/json" }
  end

  around do |example|
    original_limit = Rails.application.config.x.api.rate_limit_per_minute
    original_window = Rails.application.config.x.api.rate_limit_window_seconds
    Rails.application.config.x.api.rate_limit_per_minute = 1
    Rails.application.config.x.api.rate_limit_window_seconds = 60
    Rails.cache.clear

    example.run
  ensure
    Rails.cache.clear
    Rails.application.config.x.api.rate_limit_per_minute = original_limit
    Rails.application.config.x.api.rate_limit_window_seconds = original_window
  end

  it "throttles per token and returns 429 once threshold is exceeded" do
    owner = User.create!(email: "api-rate-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "API Rate", slug: "api-rate")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Page.create!(workspace: workspace, created_by: owner, title: "Rate target")

    first_token = ApiToken.create!(user: owner, name: "Token one")
    second_token = ApiToken.create!(user: owner, name: "Token two")

    get "/api/v1/workspaces/#{workspace.slug}/pages", headers: auth_headers(first_token)
    expect(response).to have_http_status(:ok)

    get "/api/v1/workspaces/#{workspace.slug}/pages", headers: auth_headers(first_token)
    expect(response).to have_http_status(:too_many_requests)

    get "/api/v1/workspaces/#{workspace.slug}/pages", headers: auth_headers(second_token)
    expect(response).to have_http_status(:ok)
  end
end
