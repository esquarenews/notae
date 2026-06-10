module Admin
  module UsersHelper
    def admin_user_filter_options
      Admin::UserAccountFilter::FILTER_LABELS
    end

    def admin_user_account_status(user)
      admin_user_account_tier(user).first(2)
    end

    def admin_user_account_tier(user)
      subscriptions = user.memberships.map { |membership| membership.workspace.subscription_record }
      paid_subscription = subscriptions.find { |subscription| subscription.active? && subscription.plan_key != WorkspaceSubscription::PLAN_FREE }
      trial_subscription = subscriptions.any?(&:trialing?)
      canceled_subscription = subscriptions.any?(&:canceled?)
      suspended_subscription = subscriptions.any?(&:suspended?)

      if user.removed?
        [ "Archived", "canceled", "Deactivated account" ]
      elsif user.pending_confirmation?
        [ "Pending", "pending", "Awaiting email confirmation" ]
      elsif canceled_subscription
        [ "Cancelled", "canceled", "Cancelled account" ]
      elsif user.admin_suspended? || suspended_subscription
        [ "Suspended", "suspended", "Access suspended" ]
      elsif paid_subscription
        plan_key = paid_subscription.plan_key
        [ Billing::PlanCatalog.name_for(plan_key), "active", Billing::PlanCatalog.monthly_price_label_for(plan_key) ]
      elsif trial_subscription || user.self_service_trial_active?
        [ "Trial", "trialing", admin_user_trial_description(user) ]
      elsif user.trial_expired_without_paid_access?
        [ "Expired", "canceled", "Trial ended" ]
      else
        [ user.saas_plan_name, user.saas_plan_key, Billing::PlanCatalog.monthly_price_label_for(user.saas_plan_key) ]
      end
    end

    def admin_user_trial_description(user)
      return "Trial ends #{l(user.trial_ends_at.to_date, format: :long)}" if user.trial_ends_at.present?

      "Trial account"
    end
  end
end
