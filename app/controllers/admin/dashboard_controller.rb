module Admin
  class DashboardController < BaseController
    def show
      @workspace_count = Workspace.count
      @active_workspace_count = Workspace.where(suspended_at: nil).count
      @suspended_workspace_count = Workspace.where.not(suspended_at: nil).count
      @user_count = User.count
      @subscription_counts = WorkspaceSubscription.group(:status).count
      @plan_counts = WorkspaceSubscription.group(:plan_key).count
      @trial_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_TRIALING).count
      @past_due_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_PAST_DUE).count
      @canceled_count = WorkspaceSubscription.where(status: WorkspaceSubscription::STATUS_CANCELED).count
      @mrr_aud_cents = WorkspaceSubscription
        .where(status: [ WorkspaceSubscription::STATUS_ACTIVE, WorkspaceSubscription::STATUS_TRIALING ])
        .sum { |subscription| Billing::PlanCatalog.monthly_price_aud_cents_for(subscription.plan_key) }
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
      workspace_rows = Workspace
        .includes(:workspace_subscription, memberships: :user)
        .order(updated_at: :desc)
        .limit(100)
        .to_a
      workspace_ids = workspace_rows.map(&:id)
      ai_usage_by_workspace = AiUsageLog
        .where(workspace_id: workspace_ids, created_at: Time.current.beginning_of_month..Time.current)
        .group(:workspace_id)
        .pluck(:workspace_id, Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(estimated_cost_usd), 0)"))
        .each_with_object({}) do |(workspace_id, request_count, cost_sum), usage|
          usage[workspace_id] = {
            requests: request_count.to_i,
            cost_usd: cost_sum.to_f.round(4)
          }
        end

      @workspace_admin_rows = workspace_rows.map do |workspace|
        subscription = workspace.subscription_record
        limits = subscription.effective_limits
        ai_usage = ai_usage_by_workspace.fetch(workspace.id, { requests: 0, cost_usd: 0.0 })
        usage = {
          members: workspace.memberships.size,
          ai_requests_this_month: ai_usage.fetch(:requests),
          ai_cost_usd_this_month: ai_usage.fetch(:cost_usd)
        }
        {
          workspace: workspace,
          subscription: subscription,
          users: workspace.memberships.map(&:user).compact,
          owners: workspace.memberships.select(&:owner?).map(&:user).compact,
          usage: usage,
          limits: limits,
          exceeded: {
            members: usage.fetch(:members) > limits.fetch(:members),
            ai_requests_per_month: usage.fetch(:ai_requests_this_month) > limits.fetch(:ai_requests_per_month),
            ai_monthly_budget_usd: usage.fetch(:ai_cost_usd_this_month) > limits.fetch(:ai_monthly_budget_usd)
          }
        }
      end
    end
  end
end
