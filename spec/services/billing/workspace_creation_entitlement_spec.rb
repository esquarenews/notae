require "rails_helper"

RSpec.describe Billing::WorkspaceCreationEntitlement do
  it "covers unlimited accounts without checkout using the account plan" do
    user = User.new(
      email: "unlimited-workspaces@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_BUSINESS
    )

    entitlement = described_class.new(
      user: user,
      requested_plan_key: WorkspaceSubscription::PLAN_STARTER
    )

    expect(entitlement).to be_account_covered
    expect(entitlement).not_to be_requires_checkout
    expect(entitlement.plan_key).to eq(WorkspaceSubscription::PLAN_BUSINESS)
    expect(entitlement.subscription_attributes).to include(
      plan_key: WorkspaceSubscription::PLAN_BUSINESS,
      status: WorkspaceSubscription::STATUS_ACTIVE
    )
  end

  it "keeps checkout for accounts with finite workspace allowances" do
    user = User.new(
      email: "finite-workspaces@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_STARTER
    )

    entitlement = described_class.new(
      user: user,
      requested_plan_key: WorkspaceSubscription::PLAN_TEAM
    )

    expect(entitlement).not_to be_account_covered
    expect(entitlement).to be_requires_checkout
    expect(entitlement.plan_key).to eq(WorkspaceSubscription::PLAN_TEAM)
    expect(entitlement.subscription_attributes).to include(
      plan_key: WorkspaceSubscription::PLAN_TEAM,
      status: WorkspaceSubscription::STATUS_INCOMPLETE
    )
  end
end
