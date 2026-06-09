module Admin
  class UserAccountFilter
    FILTER_LABELS = {
      "all" => "All",
      "trial" => "Trial",
      "paid" => "Paid",
      "suspended" => "Suspended",
      "archived" => "Archived"
    }.freeze
    FILTERS = FILTER_LABELS.keys.freeze

    def self.normalize(value)
      requested = value.to_s
      FILTERS.include?(requested) ? requested : "all"
    end

    def initialize(filter:, scope: User.all)
      @filter = self.class.normalize(filter)
      @scope = scope
    end

    def call
      case filter
      when "trial"
        unarchived_users(scope).where(id: trial_user_ids)
      when "paid"
        unarchived_scope = unarchived_users(scope)
        unarchived_scope
          .where(saas_plan_key: paid_plan_keys)
          .or(unarchived_scope.where(id: paid_user_ids))
      when "suspended"
        unarchived_scope = unarchived_users(scope)
        unarchived_scope
          .where("admin_suspended_until > ?", Time.current)
          .or(unarchived_scope.where(id: workspace_suspended_user_ids))
      when "archived"
        scope.where.not(removed_at: nil).or(scope.where(id: canceled_user_ids))
      else
        unarchived_users(scope)
      end
    end

    private

    attr_reader :filter, :scope

    def unarchived_users(scope)
      scope.where(removed_at: nil).where.not(id: canceled_user_ids)
    end

    def trial_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_TRIALING ])
    end

    def paid_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_ACTIVE ], paid_only: true)
    end

    def paid_plan_keys
      [ User::SAAS_PLAN_STARTER, User::SAAS_PLAN_TEAM, User::SAAS_PLAN_BUSINESS ]
    end

    def workspace_suspended_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_SUSPENDED ])
    end

    def canceled_user_ids
      user_ids_for_subscription_statuses([ WorkspaceSubscription::STATUS_CANCELED ])
    end

    def user_ids_for_subscription_statuses(statuses, paid_only: false)
      subscription_scope = Membership.joins(workspace: :workspace_subscription)
                                     .where(workspace_subscriptions: { status: statuses })
      if paid_only
        subscription_scope = subscription_scope.where(workspace_subscriptions: {
          plan_key: [
            WorkspaceSubscription::PLAN_STARTER,
            WorkspaceSubscription::PLAN_TEAM,
            WorkspaceSubscription::PLAN_BUSINESS
          ]
        })
      end

      subscription_scope.select(:user_id)
    end
  end
end
