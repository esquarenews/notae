class AdminAuditEvent < ApplicationRecord
  ACTIONS = %w[
    workspace_suspended
    workspace_reactivated
    subscription_updated
    subscription_checkout_started
    subscription_canceled
    stripe_webhook_processed
    user_limits_updated
  ].freeze

  belongs_to :actor, class_name: "User"
  belongs_to :workspace, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent_first, -> { order(created_at: :desc) }
end
