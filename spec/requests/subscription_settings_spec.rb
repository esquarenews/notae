require "rails_helper"

RSpec.describe "Subscription settings", type: :request do
  it "renders the current plan and billing placeholders" do
    user = User.create!(email: "subscription-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "Subscription settings", slug: "subscription-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_TRIALING,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
      provider_customer_id: "cus_test",
      provider_subscription_id: "sub_test",
      trial_ends_at: 3.days.from_now
    )
    sign_in user

    get workspace_subscription_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subscription")
    expect(response.body).to include("Current plan")
    expect(response.body).to include("Starter")
    expect(response.body).to include("Trialing via Stripe")
    expect(response.body).to include("1 / 3")
    expect(response.body).to include("0 / 300")
    expect(response.body).to include("Stripe environment variables are not configured yet.")
    expect(response.body).to include("Manage billing")
  end
end
