require "rails_helper"

RSpec.describe "Subscription access", type: :request do
  it "blocks normal workspace access for incomplete subscriptions but allows owners to manage billing" do
    owner = User.create!(
      email: "incomplete-owner@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_STARTER
    )
    workspace = Workspace.create!(name: "Incomplete Billing", slug: "incomplete-billing")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_INCOMPLETE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    sign_in owner

    get workspace_path(workspace.slug)
    expect(response).to redirect_to(root_path)

    get workspace_subscription_settings_path(workspace_slug: workspace.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Subscription")
  end

  it "recovers an abandoned checkout when an unlimited owner selects the workspace" do
    owner = User.create!(
      email: "covered-incomplete-owner@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_BUSINESS
    )
    workspace = Workspace.create!(name: "Covered Incomplete Billing", slug: "covered-incomplete-billing")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_INCOMPLETE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
    )
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(workspace.workspace_subscription.reload).to have_attributes(
      plan_key: WorkspaceSubscription::PLAN_BUSINESS,
      status: WorkspaceSubscription::STATUS_ACTIVE
    )
  end

  it "does not recover a Stripe-linked incomplete subscription" do
    owner = User.create!(
      email: "stripe-linked-incomplete-owner@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_BUSINESS
    )
    workspace = Workspace.create!(name: "Stripe Linked Billing", slug: "stripe-linked-billing")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_INCOMPLETE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
      provider_customer_id: "cus_linked",
      provider_subscription_id: "sub_linked"
    )
    sign_in owner

    get workspace_path(workspace.slug)

    expect(response).to redirect_to(root_path)
    expect(workspace.workspace_subscription.reload).to be_incomplete
  end
end
