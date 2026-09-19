class AdminAuditEvent < ApplicationRecord
  ACTIONS = %w[
    workspace_suspended
    workspace_reactivated
    subscription_updated
    subscription_checkout_started
    workspace_created_under_account_plan
    workspace_subscription_recovered_under_account_plan
    subscription_canceled
    stripe_webhook_processed
    user_limits_updated
    user_archived
    user_suspended
    user_removed
    user_reinstated
    user_confirmation_resent
  ].freeze

  belongs_to :actor, class_name: "User"
  belongs_to :workspace, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent_first, -> { order(created_at: :desc) }
end
