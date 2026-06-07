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
    workspace, owner = create_workspace_with_owner(name: "Admin Visible", slug: "admin-visible", owner_email: "admin-visible-owner@example.com")
    second_workspace = Workspace.create!(name: "Second Membership", slug: "second-membership")
    Membership.create!(workspace: second_workspace, user: owner, role: :member)
    owner.update!(saas_plan_key: User::SAAS_PLAN_TEAM)
    workspace.workspace_subscription.update!(plan_key: WorkspaceSubscription::PLAN_TEAM, status: WorkspaceSubscription::STATUS_ACTIVE)
    Page.create!(workspace: workspace, created_by: owner, title: "Admin Page")
    Database.create!(workspace: second_workspace, name: "Admin Database")
    AiUsageLog.create!(
      user: owner,
      workspace: workspace,
      operation: AiUsageLog::OP_ASSISTANT_QUERY,
      model: "gpt-test",
      prompt_tokens: 10,
      completion_tokens: 5,
      total_tokens: 15,
      estimated_cost_usd: 0.25
    )
    AiUsageLog.create!(
      user: owner,
      workspace: workspace,
      operation: AiUsageLog::OP_MEETING_SUMMARY,
      model: "gpt-test",
      prompt_tokens: 20,
      completion_tokens: 10,
      total_tokens: 30,
      estimated_cost_usd: 0.50
    )
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".notae-shell.notae-shell-admin")).to be_present
    expect(document.at_css("main.notae-content.notae-admin-content")).to be_present
    expect(document.at_css(".notae-admin-dashboard-shell .notae-admin-table")).to be_present
    expect(response.body).to include("SaaS admin dashboard")
    expect(response.body).to include("Stripe")
    expect(response.body).to include("Registered users")
    expect(response.body).to include("Workspaces")
    expect(response.body).to include("AI requests")
    expect(response.body).to include("Documents")
    expect(response.body).to include("Total spend")
    expect(response.body).to include("Storage")
    expect(response.body).to include("First signed")
    expect(response.body).to include("MRR")
    expect(response.body).to include("AI cost")
    expect(response.body).to include("admin-visible-owner@example.com")
    expect(response.body).to include("Team")
    expect(response.body).to include("2 workspaces")
    expect(response.body).to include("50 workspace limit")
    expect(response.body).to include("2 AI requests")
    expect(response.body).to include("$0.75")
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
                provider_subscription_id: "sub_456",
                limits_json: {
                  members: "25",
                  ai_monthly_budget_usd: "12.5",
                  ai_requests_per_month: "",
                  storage_mb: "10240"
                }
              }
            }
    end.to change(AdminAuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_workspace_path(workspace))
    subscription = workspace.reload.workspace_subscription
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_TEAM)
    expect(subscription.status).to eq(WorkspaceSubscription::STATUS_ACTIVE)
    expect(subscription.provider_customer_id).to eq("cus_123")
    expect(subscription.provider_subscription_id).to eq("sub_456")
    expect(subscription.limits_json).to include("members" => 25, "ai_monthly_budget_usd" => 12.5)
    expect(subscription.limits_json).not_to have_key("ai_requests_per_month")
    expect(subscription.limits_json).not_to have_key("storage_mb")
    expect(AdminAuditEvent.last.action).to eq("subscription_updated")
  end

  it "updates user tier and account-level limits from the user drill-in" do
    user = User.create!(
      email: "limit-user@example.com",
      password: "password123",
      saas_plan_key: User::SAAS_PLAN_FREE,
      ai_search_daily_budget_usd: 1.50,
      ai_search_semantic_rate_limit_per_minute: 24,
      ai_search_answer_rate_limit_per_minute: 12
    )
    admin = User.create!(email: "user-limit-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    expect do
      patch admin_user_path(user),
            params: {
              user: {
                saas_plan_key: User::SAAS_PLAN_STARTER,
                workspace_limit_override: "12",
                ai_search_daily_budget_usd: "5.25",
                ai_search_semantic_rate_limit_per_minute: "30",
                ai_search_answer_rate_limit_per_minute: "15"
              }
            }
    end.to change(AdminAuditEvent, :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    user.reload
    expect(user.saas_plan_key).to eq(User::SAAS_PLAN_STARTER)
    expect(user.workspace_limit_override).to eq(12)
    expect(user.workspace_limit).to eq(12)
    expect(user.ai_search_daily_budget_usd).to eq(5.25)
    expect(user.ai_search_semantic_rate_limit_per_minute).to eq(30)
    expect(user.ai_search_answer_rate_limit_per_minute).to eq(15)
    expect(AdminAuditEvent.last.action).to eq("user_limits_updated")
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
