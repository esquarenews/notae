require "rails_helper"

RSpec.describe WorkspaceSubscription, type: :model do
  it "merges plan limits with workspace-specific overrides" do
    workspace = Workspace.create!(name: "Subscription Limits", slug: "subscription-limits")
    subscription = described_class.create!(
      workspace: workspace,
      plan_key: described_class::PLAN_STARTER,
      limits_json: { "members" => 7 }
    )

    expect(subscription.effective_limits).to include(
      members: 7,
      storage_mb: 2_048,
      ai_requests_per_month: 1_000
    )
  end

  it "validates provider, status, plan, and one subscription per workspace" do
    workspace = Workspace.create!(name: "Subscription Validations", slug: "subscription-validations")
    described_class.create!(workspace: workspace)

    duplicate = described_class.new(workspace: workspace, plan_key: "nope", status: "bad", billing_provider: "other")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:workspace_id]).to include("has already been taken")
    expect(duplicate.errors[:plan_key]).to include("is not included in the list")
    expect(duplicate.errors[:status]).to include("is not included in the list")
    expect(duplicate.errors[:billing_provider]).to include("is not included in the list")
  end
end
