module Billing
  class AccountCoveredWorkspaceRecovery
    attr_reader :user, :workspace

    def initialize(user:, workspace:)
      @user = user
      @workspace = workspace
    end

    def call
      return false unless recoverable?

      WorkspaceSubscription.transaction do
        subscription.update!(
          plan_key: entitlement.plan_key,
          status: WorkspaceSubscription::STATUS_ACTIVE
        )
        AdminAuditEvent.create!(
          actor: user,
          workspace: workspace,
          target: subscription,
          action: "workspace_subscription_recovered_under_account_plan",
          metadata_json: {
            previous_plan_key: subscription.plan_key_before_last_save,
            account_plan_key: user.saas_plan_key,
            workspace_plan_key: subscription.plan_key
          }
        )
      end

      true
    end

    private

    def recoverable?
      entitlement.account_covered? &&
        owner_membership? &&
        subscription&.incomplete? &&
        subscription.provider_customer_id.blank? &&
        subscription.provider_subscription_id.blank?
    end

    def entitlement
      @entitlement ||= WorkspaceCreationEntitlement.new(
        user: user,
        requested_plan_key: subscription&.plan_key
      )
    end

    def owner_membership?
      workspace.memberships.exists?(user: user, role: Membership.roles.fetch(:owner))
    end

    def subscription
      @subscription ||= workspace.workspace_subscription
    end
  end
end
