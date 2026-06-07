require "rails_helper"

RSpec.describe "Subscription access", type: :request do
  it "blocks normal workspace access for incomplete subscriptions but allows owners to manage billing" do
    owner = User.create!(email: "incomplete-owner@example.com", password: "password123")
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
end
