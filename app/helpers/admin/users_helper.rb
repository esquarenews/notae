module Admin
  module UsersHelper
    def admin_user_filter_options
      Admin::UserAccountFilter::FILTER_LABELS
    end

    def admin_user_account_status(user)
      subscriptions = user.memberships.map { |membership| membership.workspace.subscription_record }
      paid_subscription = subscriptions.any? { |subscription| subscription.active? && subscription.plan_key != WorkspaceSubscription::PLAN_FREE }
      trial_subscription = subscriptions.any?(&:trialing?)
      canceled_subscription = subscriptions.any?(&:canceled?)
      suspended_subscription = subscriptions.any?(&:suspended?)

      if user.removed?
        [ "Archived", "canceled" ]
      elsif user.pending_confirmation?
        [ "Pending", "pending" ]
      elsif canceled_subscription
        [ "Cancelled", "canceled" ]
      elsif user.admin_suspended? || suspended_subscription
        [ "Suspended", "suspended" ]
      elsif trial_subscription || user.self_service_trial_active?
        [ "Trial", "trialing" ]
      elsif user.trial_expired_without_paid_access?
        [ "Expired", "canceled" ]
      elsif paid_subscription
        [ "Paid", "active" ]
      else
        [ user.saas_plan_name, user.saas_plan_key ]
      end
    end
  end
end
