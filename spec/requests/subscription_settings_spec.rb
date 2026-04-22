require "rails_helper"

RSpec.describe "Subscription settings", type: :request do
  it "renders the current plan and billing placeholders" do
    user = User.create!(email: "subscription-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "Subscription settings", slug: "subscription-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    get workspace_subscription_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subscription")
    expect(response.body).to include("Current plan")
    expect(response.body).to include("Free")
    expect(response.body).to include("Trialing via Fat Zebra")
    expect(response.body).to include("1 / 1")
    expect(response.body).to include("0 / 100")
    expect(response.body).to include("Gateway credentials are not configured yet.")
    expect(response.body).to include("Change plan")
  end
end
