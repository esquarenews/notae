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
    expect(response.body).to include("SaaS admin dashboard")
    expect(response.body).to include("Fat Zebra")
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
                billing_provider: WorkspaceSubscription::PROVIDER_FAT_ZEBRA,
                provider_customer_id: "cus_123",
                provider_subscription_id: "plan_456"
              }
            }
    end.to change(AdminAuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_workspace_path(workspace))
    subscription = workspace.reload.workspace_subscription
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_TEAM)
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(subscription.provider_customer_id).to eq("cus_123")
    expect(subscription.provider_subscription_id).to eq("plan_456")
    expect(AdminAuditEvent.last.action).to eq("subscription_updated")
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
