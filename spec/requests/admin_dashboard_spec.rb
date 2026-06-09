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
    expect(document.at_css(".notae-admin-user-tier-row.notae-admin-user-tier-team")).to be_present
    filter_links = document.css("nav[aria-label='User account filters'] a").map { |link| [ link.text.squish, link["href"] ] }
    expect(filter_links).to include([ "All", admin_root_path(filter: "all") ])
    expect(filter_links).to include([ "Trial", admin_root_path(filter: "trial") ])
    expect(filter_links).to include([ "Paid", admin_root_path(filter: "paid") ])
    expect(filter_links).to include([ "Suspended", admin_root_path(filter: "suspended") ])
    expect(filter_links).to include([ "Archived", admin_root_path(filter: "archived") ])
    expect(response.body).to include("SaaS admin dashboard")
    expect(response.body).to include("Stripe")
    expect(response.body).to include("Registered users")
    expect(response.body).to include("AI requests")
    expect(response.body).to include("Documents")
    expect(response.body).to include("Total spend")
    expect(response.body).to include("Storage")
    expect(response.body).to include("First signed")
    expect(response.body).to include("MRR")
    expect(response.body).to include("AI cost")
    expect(response.body).to include("admin-visible-owner@example.com")
    expect(response.body).to include("Team")
    expect(response.body).to include("2 AI requests")
    expect(response.body).to include("$0.75")
    expect(response.body).to include("Archive")
    expect(response.body).not_to include("<th>Workspaces</th>")
    expect(response.body).not_to include("workspace limit")
  end

  it "filters and archives users from the admin dashboard" do
    admin = User.create!(email: "dashboard-filter-admin@example.com", password: "password123", super_admin: true)
    trial_workspace, trial_user = create_workspace_with_owner(name: "Dashboard Trial Account", slug: "dashboard-trial-account", owner_email: "dashboard-trial-user@example.com")
    paid_workspace, paid_user = create_workspace_with_owner(name: "Dashboard Paid Account", slug: "dashboard-paid-account", owner_email: "dashboard-paid-user@example.com")
    canceled_workspace, canceled_user = create_workspace_with_owner(name: "Dashboard Canceled Account", slug: "dashboard-canceled-account", owner_email: "dashboard-canceled-user@example.com")
    archived_user = User.create!(email: "dashboard-archived-user@example.com", password: "password123", removed_at: 1.day.ago)

    trial_workspace.workspace_subscription.update!(status: WorkspaceSubscription::STATUS_TRIALING)
    paid_workspace.workspace_subscription.update!(plan_key: WorkspaceSubscription::PLAN_TEAM, status: WorkspaceSubscription::STATUS_ACTIVE)
    canceled_workspace.workspace_subscription.update!(status: WorkspaceSubscription::STATUS_CANCELED)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("User account filters")
    expect(response.body).to include("Archive")
    expect(response.body).to include(trial_user.email)
    expect(response.body).to include(paid_user.email)
    expect(response.body).not_to include(canceled_user.email)
    expect(response.body).not_to include(archived_user.email)

    get admin_root_path(filter: "trial")
    expect(response.body).to include(trial_user.email)
    expect(response.body).not_to include(paid_user.email)

    get admin_root_path(filter: "paid")
    expect(response.body).to include(paid_user.email)
    expect(response.body).not_to include(trial_user.email)

    get admin_root_path(filter: "archived")
    expect(response.body).to include(canceled_user.email)
    expect(response.body).to include(archived_user.email)
    expect(response.body).not_to include(paid_user.email)

    expect do
      patch archive_admin_user_path(trial_user, filter: "trial", return_to: "dashboard")
    end.to change(AdminAuditEvent.where(action: "user_archived"), :count).by(1)

    expect(response).to redirect_to(admin_root_path(filter: "trial"))
    trial_user.reload
    expect(trial_user).to be_removed
    expect(trial_user).not_to be_active_for_authentication
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

  it "does not change existing billing subscription pricing when an admin manually changes user tier" do
    workspace, user = create_workspace_with_owner(
      name: "Manual Tier Billing",
      slug: "manual-tier-billing",
      owner_email: "manual-tier-billing-user@example.com"
    )
    subscription = workspace.workspace_subscription
    subscription.update!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_ACTIVE,
      provider_customer_id: "cus_manual_tier",
      provider_subscription_id: "sub_manual_tier"
    )
    admin = User.create!(email: "manual-tier-billing-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    patch admin_user_path(user),
          params: {
            user: {
              saas_plan_key: User::SAAS_PLAN_BUSINESS,
              workspace_limit_override: ""
            }
          }

    expect(response).to redirect_to(admin_user_path(user))
    expect(user.reload.saas_plan_key).to eq(User::SAAS_PLAN_BUSINESS)
    subscription.reload
    expect(subscription.plan_key).to eq(WorkspaceSubscription::PLAN_STARTER)
    expect(subscription.provider_customer_id).to eq("cus_manual_tier")
    expect(subscription.provider_subscription_id).to eq("sub_manual_tier")
  end

  it "does not show user workspace memberships on the user detail page" do
    user = User.create!(email: "workspace-summary-user@example.com", password: "password123", saas_plan_key: User::SAAS_PLAN_TEAM)
    first_workspace = Workspace.create!(name: "Hidden Workspace One", slug: "hidden-workspace-one")
    second_workspace = Workspace.create!(name: "Hidden Workspace Two", slug: "hidden-workspace-two")
    Membership.create!(workspace: first_workspace, user: user, role: :owner)
    Membership.create!(workspace: second_workspace, user: user, role: :member)
    admin = User.create!(email: "workspace-summary-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    get admin_user_path(user)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    topbar_links = document.css("header a").map { |link| [ link.text.squish, link["href"] ] }
    expect(topbar_links).to include([ "Users", admin_users_path ])
    expect(topbar_links).to include([ "Dashboard", admin_root_path ])
    card_labels = document.css(".notae-ai-analytics-card .notae-pref-label").map { |label| label.text.squish }
    expect(card_labels).not_to include("Workspaces")
    expect(response.body).to include("Daily AI budget USD")
    expect(response.body).to include("Semantic search requests / min")
    expect(response.body).to include("Answer generation requests / min")
    expect(response.body).not_to include("Current workspace count")
    expect(response.body).not_to include("Workspace memberships")
    expect(response.body).not_to include("Hidden Workspace One")
    expect(response.body).not_to include("Hidden Workspace Two")
  end

  it "redirects the hidden workspace index to the filtered users page" do
    admin = User.create!(email: "workspace-index-admin@example.com", password: "password123", super_admin: true)
    create_workspace_with_owner(
      name: "Hidden Admin Workspace",
      slug: "hidden-admin-workspace",
      owner_email: "hidden-admin-workspace-owner@example.com"
    )
    sign_in admin

    get admin_workspaces_path

    expect(response).to redirect_to(admin_users_path)

    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("User account filters")
    expect(response.body).to include("All")
    expect(response.body).to include("Trial")
    expect(response.body).to include("Paid")
    expect(response.body).to include("Suspended")
    expect(response.body).to include("Archived")
    expect(response.body).not_to include("Hidden Admin Workspace")
  end

  it "filters admin users by account state and archives users from the list" do
    admin = User.create!(email: "user-filter-admin@example.com", password: "password123", super_admin: true)
    trial_workspace, trial_user = create_workspace_with_owner(name: "Trial Account", slug: "trial-account", owner_email: "trial-account-user@example.com")
    paid_workspace, paid_user = create_workspace_with_owner(name: "Paid Account", slug: "paid-account", owner_email: "paid-account-user@example.com")
    suspended_workspace, suspended_user = create_workspace_with_owner(name: "Suspended Account", slug: "suspended-account", owner_email: "suspended-account-user@example.com")
    canceled_workspace, canceled_user = create_workspace_with_owner(name: "Canceled Account", slug: "canceled-account", owner_email: "canceled-account-user@example.com")
    manual_paid_user = User.create!(email: "manual-paid-account-user@example.com", password: "password123", saas_plan_key: User::SAAS_PLAN_TEAM)
    archived_user = User.create!(email: "archived-account-user@example.com", password: "password123", removed_at: 1.day.ago)

    trial_workspace.workspace_subscription.update!(status: WorkspaceSubscription::STATUS_TRIALING)
    paid_workspace.workspace_subscription.update!(plan_key: WorkspaceSubscription::PLAN_TEAM, status: WorkspaceSubscription::STATUS_ACTIVE)
    suspended_user.suspend_for_week!
    suspended_workspace.workspace_subscription.update!(status: WorkspaceSubscription::STATUS_SUSPENDED)
    canceled_workspace.workspace_subscription.update!(status: WorkspaceSubscription::STATUS_CANCELED)
    sign_in admin

    get admin_users_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("User account filters")
    expect(response.body).to include("Archive")
    expect(response.body).to include(trial_user.email)
    expect(response.body).to include(paid_user.email)
    expect(response.body).to include(suspended_user.email)
    expect(response.body).not_to include(archived_user.email)
    expect(response.body).not_to include(canceled_user.email)

    get admin_users_path(filter: "trial")
    expect(response.body).to include(trial_user.email)
    expect(response.body).not_to include(paid_user.email)

    get admin_users_path(filter: "paid")
    expect(response.body).to include(paid_user.email)
    expect(response.body).to include(manual_paid_user.email)
    expect(response.body).not_to include(trial_user.email)

    get admin_users_path(filter: "suspended")
    expect(response.body).to include(suspended_user.email)
    expect(response.body).not_to include(paid_user.email)

    get admin_users_path(filter: "archived")
    expect(response.body).to include(archived_user.email)
    expect(response.body).to include(canceled_user.email)
    expect(response.body).not_to include(paid_user.email)

    expect do
      patch archive_admin_user_path(trial_user, filter: "trial")
    end.to change(AdminAuditEvent.where(action: "user_archived"), :count).by(1)

    expect(response).to redirect_to(admin_users_path(filter: "trial"))
    trial_user.reload
    expect(trial_user).to be_removed
    expect(trial_user).not_to be_active_for_authentication
  end

  it "suspends, removes, and reinstates user accounts from the admin user detail page" do
    user = User.create!(email: "account-control-user@example.com", password: "password123", saas_plan_key: User::SAAS_PLAN_TEAM)
    api_token = user.api_tokens.create!(name: "Admin control token", scopes_json: [ ApiToken::SCOPE_PAGES_READ ])
    admin = User.create!(email: "account-control-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    get admin_user_path(user)

    expect(response.body).to include("Account controls")
    expect(response.body).to include("Suspend for one week")
    expect(response.body).to include("Delete user")
    expect(response.body).to include("Manual admin tier changes update Notae entitlements only")
    expect(response.body).to include("They do not change the user's existing Stripe subscription price")

    expect do
      patch suspend_admin_user_path(user)
    end.to change(AdminAuditEvent.where(action: "user_suspended"), :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    expect(user.reload).to be_admin_suspended
    expect(user.admin_suspended_until).to be_within(5.seconds).of(1.week.from_now)
    expect(user).not_to be_active_for_authentication

    expect do
      patch remove_admin_user_path(user)
    end.to change(AdminAuditEvent.where(action: "user_removed"), :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    user.reload
    expect(user).to be_removed
    expect(user).not_to be_admin_suspended
    expect(user).not_to be_active_for_authentication
    expect(api_token.reload).to be_revoked

    get admin_user_path(user)

    expect(response.body).to include("Reinstate on Free tier")
    expect(response.body).not_to include("Suspend for one week")

    expect do
      patch reinstate_admin_user_path(user)
    end.to change(AdminAuditEvent.where(action: "user_reinstated"), :count).by(1)

    expect(response).to redirect_to(admin_user_path(user))
    user.reload
    expect(user).not_to be_removed
    expect(user.saas_plan_key).to eq(User::SAAS_PLAN_FREE)
    expect(user.admin_free_tier_ends_at).to be_within(5.seconds).of(1.week.from_now)
    expect(user).to be_active_for_authentication
  end

  it "does not reinstate users unless they have been removed" do
    user = User.create!(email: "active-reinstate-user@example.com", password: "password123")
    admin = User.create!(email: "active-reinstate-admin@example.com", password: "password123", super_admin: true)
    sign_in admin

    patch reinstate_admin_user_path(user)

    expect(response).to redirect_to(admin_user_path(user))
    follow_redirect!
    expect(response.body).to include("Only removed users can be reinstated.")
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
