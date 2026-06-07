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
    expect(response.body).to include("Stripe is not ready yet")
    expect(response.body).to include("Stripe billing setup is incomplete")
    expect(response.body).not_to include("STRIPE_SECRET_KEY")
    expect(response.body).not_to include("STRIPE_PRICE_STARTER")
    expect(response.body).to include("Manage billing")
  end

  it "renders a warning instead of failing when Stripe configuration checks raise" do
    user = User.create!(email: "subscription-stripe-error@example.com", password: "password123")
    workspace = Workspace.create!(name: "Subscription stripe error", slug: "subscription-stripe-error")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_ACTIVE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    allow(Billing::StripeGateway).to receive(:configuration_status).and_return(
      configured: false,
      missing: [],
      message: "Stripe configuration could not be checked: test failure"
    )
    sign_in user

    get workspace_subscription_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stripe is not ready yet")
    expect(response.body).to include("Stripe configuration could not be checked")
    expect(response.body).to include("Billing controls are disabled")
  end

  it "does not require Stripe configuration for super-admin granted free workspaces" do
    user = User.create!(email: "subscription-free@example.com", password: "password123")
    workspace = Workspace.create!(name: "Subscription free", slug: "subscription-free")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_FREE,
      status: WorkspaceSubscription::STATUS_ACTIVE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    allow(Billing::StripeGateway).to receive(:configuration_status).and_raise("should not check Stripe for free tier")
    sign_in user

    get workspace_subscription_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Free")
    expect(response.body).to include("super-admin granted free tier")
    expect(response.body).not_to include("Stripe is not ready yet")
  end
end
