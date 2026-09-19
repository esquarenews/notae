module Billing
  class WorkspaceCreationEntitlement
    attr_reader :user, :requested_plan_key

    def initialize(user:, requested_plan_key:)
      @user = user
      @requested_plan_key = requested_plan_key.to_s
    end

    def account_covered?
      user.platform_admin? || user.workspace_limit_unlimited?
    end

    def requires_checkout?
      !account_covered?
    end

    def plan_key
      return account_plan_key if account_covered?

      requested_plan_key
    end

    def subscription_attributes
      {
        plan_key: plan_key,
        status: account_covered? ? WorkspaceSubscription::STATUS_ACTIVE : WorkspaceSubscription::STATUS_INCOMPLETE,
        billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
      }
    end

    private

    def account_plan_key
      plan = user.saas_plan_key.to_s
      return plan if WorkspaceSubscription::PLAN_KEYS.include?(plan)

      WorkspaceSubscription::PLAN_FREE
    end
  end
end
