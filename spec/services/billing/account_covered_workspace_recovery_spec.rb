require "rails_helper"

RSpec.describe Billing::AccountCoveredWorkspaceRecovery do
  def create_workspace_with_subscription(user:, slug:, provider_customer_id: nil, provider_subscription_id: nil)
    workspace = Workspace.create!(name: slug.humanize, slug: slug)
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_INCOMPLETE,
      billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
      provider_customer_id: provider_customer_id,
      provider_subscription_id: provider_subscription_id
    )
    workspace
  end

  it "recovers an abandoned checkout for an unlimited workspace owner" do
    user = User.create!(
      email: "workspace-recovery-owner@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_BUSINESS
    )
    workspace = create_workspace_with_subscription(user: user, slug: "recoverable-workspace")

    expect do
      expect(described_class.new(user: user, workspace: workspace).call).to be(true)
    end.to change(AdminAuditEvent, :count).by(1)

    subscription = workspace.workspace_subscription.reload
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_BUSINESS)
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(AdminAuditEvent.last.action).to eq("workspace_subscription_recovered_under_account_plan")
  end

  it "does not recover a finite account or a Stripe-linked subscription" do
    finite_user = User.create!(
      email: "finite-workspace-recovery@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_STARTER
    )
    finite_workspace = create_workspace_with_subscription(user: finite_user, slug: "finite-recovery")
    unlimited_user = User.create!(
      email: "linked-workspace-recovery@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_BUSINESS
    )
    linked_workspace = create_workspace_with_subscription(
      user: unlimited_user,
      slug: "linked-recovery",
      provider_customer_id: "cus_linked",
      provider_subscription_id: "sub_linked"
    )

    expect(described_class.new(user: finite_user, workspace: finite_workspace).call).to be(false)
    expect(described_class.new(user: unlimited_user, workspace: linked_workspace).call).to be(false)
    expect(finite_workspace.workspace_subscription.reload).to be_incomplete
    expect(linked_workspace.workspace_subscription.reload).to be_incomplete
  end
end
