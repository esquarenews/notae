require "rails_helper"

RSpec.describe "Stripe webhooks", type: :request do
  it "reconciles checkout completion into a trialing workspace subscription" do
    user = User.create!(email: "stripe-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Stripe Checkout", slug: "stripe-checkout")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    subscription = workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_INCOMPLETE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    trial_end = 7.days.from_now.to_i
    current_period_end = 1.month.from_now.to_i

    allow(Stripe::Subscription).to receive(:retrieve).with("sub_test").and_return(
      {
        id: "sub_test",
        customer: "cus_test",
        status: "trialing",
        trial_end: trial_end,
        current_period_end: current_period_end,
        metadata: { workspace_subscription_id: subscription.id }
      }
    )

    expect do
      post stripe_webhook_path,
           params: {
             id: "evt_checkout",
             type: "checkout.session.completed",
             data: {
               object: {
                 id: "cs_test",
                 object: "checkout.session",
                 customer: "cus_test",
                 subscription: "sub_test",
                 metadata: { workspace_subscription_id: subscription.id }
               }
             }
           }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }
    end.to change(StripeWebhookEvent, :count).by(1)

    expect(response).to have_http_status(:ok)
    subscription.reload
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_TRIALING)
    expect(subscription.provider_customer_id).to eq("cus_test")
    expect(subscription.provider_subscription_id).to eq("sub_test")
    expect(subscription.trial_ends_at.to_i).to eq(trial_end)
  end

  it "deduplicates Stripe webhook events by provider event id" do
    payload = {
      id: "evt_duplicate",
      type: "customer.subscription.updated",
      data: { object: { id: "sub_missing", object: "subscription", status: "active" } }
    }.to_json

    post stripe_webhook_path, params: payload, headers: { "CONTENT_TYPE" => "application/json" }

    expect do
      post stripe_webhook_path, params: payload, headers: { "CONTENT_TYPE" => "application/json" }
    end.not_to change(StripeWebhookEvent, :count)
  end
end
