require "rails_helper"

RSpec.describe "Admin dashboard", type: :request do
  def create_workspace_with_owner(name:, slug:, owner_email:)
    owner = User.create!(email: owner_email, password: "password123")
    workspace = Workspace.create!(name: name, slug: slug)
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    workspace.create_workspace_subscription!
    [ workspace, owner ]
  end

  it "blocks signed-in users who are not platform admins" do
    user = User.create!(email: "not-platform-admin@example.com", password: "password123")
    sign_in user

    get admin_root_path

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("not authorized")
  end

  it "allows super admins to view platform tenancy and billing state" do
    admin = User.create!(email: "platform-admin@example.com", password: "password123", super_admin: true)
    create_workspace_with_owner(name: "Admin Visible", slug: "admin-visible", owner_email: "admin-visible-owner@example.com")
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("main.notae-content.notae-admin-content")).to be_present
    expect(document.at_css(".notae-settings-shell.notae-admin-shell > .notae-settings-content")).to be_present
    expect(response.body).to include("SaaS admin dashboard")
    expect(response.body).to include("Stripe")
    expect(response.body).to include("/webhooks/stripe")
    expect(response.body).to include("MRR")
    expect(response.body).to include("AI cost risk")
    expect(response.body).to include("Admin Visible")
  end

  it "allows env-allowlisted admins without changing the user row" do
    admin = User.create!(email: "env-platform-admin@example.com", password: "password123")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("NOTAE_PLATFORM_ADMIN_EMAILS", "").and_return(" env-platform-admin@example.com ")
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("SaaS admin dashboard")
  end

  it "updates workspace subscription state and writes an admin audit event" do
    workspace, = create_workspace_with_owner(name: "Billing Workspace", slug: "billing-workspace", owner_email: "billing-owner@example.com")
    admin = User.create!(email: "billing-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    expect do
      patch admin_workspace_path(workspace),
            params: {
              workspace_subscription: {
                plan_key: WorkspaceSubscription::PLAN_TEAM,
                status: WorkspaceSubscription::STATUS_ACTIVE,
                billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
                provider_customer_id: "cus_123",
                provider_subscription_id: "sub_456"
              }
            }
    end.to change(AdminAuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_workspace_path(workspace))
    subscription = workspace.reload.workspace_subscription
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_TEAM)
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(subscription.provider_customer_id).to eq("cus_123")
    expect(subscription.provider_subscription_id).to eq("sub_456")
    expect(AdminAuditEvent.last.action).to eq("subscription_updated")
  end

  it "lets a platform admin grant the free tier without Stripe references" do
    workspace, = create_workspace_with_owner(name: "Free Grant", slug: "free-grant", owner_email: "free-grant-owner@example.com")
    workspace.workspace_subscription.update!(
      plan_key: WorkspaceSubscription::PLAN_TEAM,
      status: WorkspaceSubscription::STATUS_ACTIVE,
      provider_customer_id: "cus_existing",
      provider_subscription_id: "sub_existing",
      trial_ends_at: 2.days.from_now,
      current_period_ends_at: 1.month.from_now
    )
    admin = User.create!(email: "free-grant-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    patch admin_workspace_path(workspace),
          params: {
            workspace_subscription: {
              plan_key: WorkspaceSubscription::PLAN_FREE,
              status: WorkspaceSubscription::STATUS_PAST_DUE,
              billing_provider: WorkspaceSubscription::PROVIDER_STRIPE,
              provider_customer_id: "cus_should_clear",
              provider_subscription_id: "sub_should_clear"
            }
          }

    subscription = workspace.reload.workspace_subscription
    expect(response).to redirect_to(admin_workspace_path(workspace))
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_FREE)
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(subscription.provider_customer_id).to be_blank
    expect(subscription.provider_subscription_id).to be_blank
    expect(subscription.trial_ends_at).to be_blank
    expect(subscription.current_period_ends_at).to be_blank
  end

  it "suspends and reactivates workspace access from the admin console" do
    workspace, owner = create_workspace_with_owner(name: "Suspendable", slug: "suspendable", owner_email: "suspendable-owner@example.com")
    admin = User.create!(email: "suspension-admin@example.com", password: "password123", super_admin: true)

    sign_in admin
    expect do
      patch suspend_admin_workspace_path(workspace), params: { workspace: { suspension_reason: "Billing overdue" } }
    end.to change(AdminAuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_workspace_path(workspace))
    expect(workspace.reload).to be_suspended
    expect(workspace.suspension_reason).to eq("Billing overdue")
    expect(workspace.workspace_subscription.status).to eq(WorkspaceSubscription::STATUS_SUSPENDED)

    sign_out admin
    sign_in owner
    get workspace_path(workspace.slug)
    expect(response).to have_http_status(:not_found)

    sign_out owner
    sign_in admin
    expect do
      patch reactivate_admin_workspace_path(workspace)
    end.to change(AdminAuditEvent, :count).by(1)

    expect(workspace.reload).not_to be_suspended
    expect(workspace.workspace_subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)

    sign_out admin
    sign_in owner
    get workspace_path(workspace.slug)
    expect(response).to have_http_status(:ok)
  end
end
