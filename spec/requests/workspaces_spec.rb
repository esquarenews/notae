require "rails_helper"

RSpec.describe "Workspaces", type: :request do
  CheckoutSession = Struct.new(:id, :url, keyword_init: true)

  def missing_table_error(table_name)
    ActiveRecord::StatementInvalid.new("PG::UndefinedTable: ERROR: relation \"#{table_name}\" does not exist")
  end

  def stub_stripe_checkout(url: "https://checkout.stripe.test/session")
    allow_any_instance_of(Billing::StripeGateway)
      .to receive(:create_checkout_session!)
      .and_return(CheckoutSession.new(id: "cs_test_123", url: url))
  end

  it "renders new workspace when optional AI tables are unavailable" do
    user = User.create!(email: "workspace-new-owner@example.com", password: "password123")
    workspace = Workspace.create!(name: "Existing", slug: "existing")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    allow(AiConversation).to receive(:for_user).and_raise(missing_table_error("ai_conversations"))
    allow(AiUsageLog).to receive(:for_user_and_workspace).and_raise(missing_table_error("ai_usage_logs"))

    get new_workspace_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create Workspace")
    expect(response.body).to include("Workspace colour")
    expect(response.body).to include("notae-workspace-color-option")
  end

  it "renders new workspace for a signed-in user with no existing workspaces" do
    user = User.create!(email: "workspace-first-owner@example.com", password: "password123")
    sign_in user

    get new_workspace_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Create Workspace")
  end

  it "lets an authenticated user create a workspace and become owner" do
    user = User.create!(email: "owner@example.com", password: "password123")
    sign_in user
    stub_stripe_checkout

    expect do
      post workspaces_path,
           params: {
             workspace: {
               name: "Product",
               slug: "product-team",
               workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.third.fetch(:value),
               plan_key: WorkspaceSubscription::PLAN_TEAM
             }
           }
    end.to change(Workspace, :count).by(1)
      .and change(WorkspaceSubscription, :count).by(1)

    workspace = Workspace.find_by!(slug: "product-team")

    expect(response).to redirect_to("https://checkout.stripe.test/session")
    expect(Membership.find_by!(workspace: workspace, user: user).role).to eq("owner")
    expect(workspace.workspace_color).to eq(Workspace::WORKSPACE_COLOR_OPTIONS.third.fetch(:value))
    expect(workspace.workspace_subscription.plan_key).to eq(WorkspaceSubscription::PLAN_TEAM)
    expect(workspace.workspace_subscription.status).to eq(WorkspaceSubscription::STATUS_INCOMPLETE)
    expect(workspace.workspace_subscription.billing_provider).to eq(WorkspaceSubscription::PROVIDER_STRIPE)
  end

  it "derives the workspace slug from the name when slug is omitted" do
    user = User.create!(email: "workspace-slug-derived@example.com", password: "password123")
    sign_in user
    stub_stripe_checkout

    expect do
      post workspaces_path, params: { workspace: { name: "Growth Team", slug: "" } }
    end.to change(Workspace, :count).by(1)

    workspace = Workspace.find_by!(slug: "growth-team")
    expect(response).to redirect_to("https://checkout.stripe.test/session")
    expect(Membership.find_by!(workspace: workspace, user: user).role).to eq("owner")
    expect(workspace.workspace_color).to eq(Workspace::DEFAULT_COLOR)
  end

  it "restricts workspace access to members" do
    owner = User.create!(email: "ws-owner@example.com", password: "password123")
    outsider = User.create!(email: "outsider@example.com", password: "password123")
    workspace = Workspace.create!(name: "Engineering", slug: "engineering")
    Membership.create!(workspace: workspace, user: owner, role: :owner)

    sign_in outsider
    get workspace_path(workspace.slug)

    expect(response).to have_http_status(:not_found)
  end
end
