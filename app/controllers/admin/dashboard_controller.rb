module Admin
  class DashboardController < BaseController
    def show
      @workspace_count = Workspace.count
      @active_workspace_count = Workspace.where(suspended_at: nil).count
      @suspended_workspace_count = Workspace.where.not(suspended_at: nil).count
      @user_count = User.count
      @subscription_counts = WorkspaceSubscription.group(:status).count
      @plan_counts =
        if User.saas_plan_key_column_available?
          User.group(:saas_plan_key).count
        else
          { User::SAAS_PLAN_FREE => @user_count }
        end
      @trial_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_TRIALING).count
      @past_due_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_PAST_DUE).count
      @canceled_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_CANCELED).count
      @mrr_aud_cents = User.sum { |user| Billing::PlanCatalog.monthly_price_aud_cents_for(user.saas_plan_key) }
      @ai_cost_this_month_usd = AiUsageLog.where(created_at: Time.current.beginning_of_month..Time.current).sum(:estimated_cost_usd).to_f
      @high_ai_cost_workspaces = Workspace
        .joins(:ai_usage_logs)
        .where(ai_usage_logs: { created_at: Time.current.beginning_of_month..Time.current })
        .group("workspaces.id")
        .select("workspaces.*, SUM(ai_usage_logs.estimated_cost_usd) AS monthly_ai_cost_usd")
        .order(Arel.sql("monthly_ai_cost_usd DESC"))
        .limit(5)
      @recent_workspaces = Workspace.includes(:workspace_subscription).order(updated_at: :desc).limit(8)
      @recent_admin_events = AdminAuditEvent.recent_first.includes(:actor, :workspace).limit(12)
      @billing_provider_ready = Billing::StripeGateway.configured?
      @stripe_webhook_path = stripe_webhook_path
      @stripe_webhook_auth_ready = Billing::StripeGateway.webhook_configured?
      @failed_stripe_webhook_count = StripeWebhookEvent.where(status: StripeWebhookEvent::STATUS_FAILED).count
      users = User
        .includes(memberships: :workspace)
        .order(created_at: :desc)
        .limit(100)
        .to_a
      user_summaries = Admin::UserUsageSummary.new(users: users).call

      @user_admin_rows = users.map do |user|
        {
          user: user,
          summary: user_summaries.fetch(user)
        }
      end
    end
  end
end
