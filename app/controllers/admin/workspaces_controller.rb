module Admin
  class WorkspacesController < BaseController
    before_action :set_workspace, only: %i[show update suspend reactivate]

    def index
      @workspaces = Workspace
        .includes(:workspace_subscription, :memberships)
        .order(updated_at: :desc)
        .limit(100)
    end

    def show
      @subscription = @workspace.subscription_record
      @tenant_snapshot = TenantLimits::Snapshot.new(workspace: @workspace).call
      @memberships = @workspace.memberships.includes(:user).order(:created_at)
      @recent_admin_events = AdminAuditEvent.where(workspace: @workspace).recent_first.includes(:actor).limit(12)
    end

    def update
      subscription = @workspace.subscription_record
      subscription.assign_attributes(subscription_params)
      subscription.limits_json = normalized_limits_json(subscription) if params[:workspace_subscription].key?(:limits_json)
      normalize_free_subscription!(subscription)
      subscription.save!

      record_admin_audit!(
        action: "subscription_updated",
        workspace: @workspace,
        target: subscription,
        metadata: subscription_params.to_h
      )

      redirect_to admin_workspace_path(@workspace), notice: "Subscription updated."
    end

    def suspend
      @workspace.update!(
        suspended_at: Time.current,
        suspension_reason: params.dig(:workspace, :suspension_reason).to_s.strip.presence || "Suspended by platform admin"
      )
      @workspace.subscription_record.update!(status: WorkspaceSubscription::STATUS_SUSPENDED)
      record_admin_audit!(
        action: "workspace_suspended",
        workspace: @workspace,
        target: @workspace,
        metadata: { reason: @workspace.suspension_reason }
      )

      redirect_to admin_workspace_path(@workspace), notice: "Workspace suspended."
    end

    def reactivate
      @workspace.update!(suspended_at: nil, suspension_reason: nil)
      @workspace.subscription_record.update!(status: WorkspaceSubscription::STATUS_ACTIVE)
      record_admin_audit!(
        action: "workspace_reactivated",
        workspace: @workspace,
        target: @workspace
      )

      redirect_to admin_workspace_path(@workspace), notice: "Workspace reactivated."
    end

    private

    def set_workspace
      @workspace = Workspace.find(params[:id])
    end

    def subscription_params
      params.require(:workspace_subscription).permit(
        :plan_key,
        :status,
        :billing_provider,
        :provider_customer_id,
        :provider_subscription_id,
        :trial_ends_at,
        :current_period_ends_at,
        limits_json: [
          :members,
          :storage_mb,
          :ai_requests_per_month,
          :ai_monthly_budget_usd,
          :integrations,
          :exports_per_month
        ]
      )
    end

    def normalized_limits_json(subscription)
      plan_limits = Billing::PlanCatalog.limits_for(subscription.plan_key)
      raw_limits = subscription_params.fetch(:limits_json, {}).to_h

      plan_limits.each_with_object({}) do |(key, plan_value), overrides|
        raw_value = raw_limits[key.to_s].to_s.strip
        next if raw_value.blank?

        normalized_value =
          if key == :ai_monthly_budget_usd
            BigDecimal(raw_value).to_f
          else
            Integer(raw_value)
          end
        overrides[key.to_s] = normalized_value if normalized_value != plan_value
      rescue ArgumentError
        next
      end
    end

    def normalize_free_subscription!(subscription)
      return unless subscription.plan_key == WorkspaceSubscription::PLAN_FREE

      subscription.status = WorkspaceSubscription::STATUS_ACTIVE
      subscription.provider_customer_id = nil
      subscription.provider_subscription_id = nil
      subscription.trial_ends_at = nil
      subscription.current_period_ends_at = nil
    end
  end
end
