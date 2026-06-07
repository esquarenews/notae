class WorkspaceSubscription < ApplicationRecord
  PLAN_FREE = "free".freeze
  PLAN_STARTER = "starter".freeze
  PLAN_TEAM = "team".freeze
  PLAN_BUSINESS = "business".freeze
  PLAN_KEYS = [ PLAN_FREE, PLAN_STARTER, PLAN_TEAM, PLAN_BUSINESS ].freeze

  STATUS_TRIALING = "trialing".freeze
  STATUS_ACTIVE = "active".freeze
  STATUS_PAST_DUE = "past_due".freeze
  STATUS_CANCELED = "canceled".freeze
  STATUS_SUSPENDED = "suspended".freeze
  STATUS_INCOMPLETE = "incomplete".freeze
  STATUSES = [ STATUS_INCOMPLETE, STATUS_TRIALING, STATUS_ACTIVE, STATUS_PAST_DUE, STATUS_CANCELED, STATUS_SUSPENDED ].freeze

  PROVIDER_STRIPE = "stripe".freeze
  PROVIDERS = [ PROVIDER_STRIPE ].freeze

  belongs_to :workspace

  validates :plan_key, presence: true, inclusion: { in: PLAN_KEYS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :billing_provider, presence: true, inclusion: { in: PROVIDERS }
  validates :workspace_id, uniqueness: true

  scope :recent_first, -> { order(updated_at: :desc) }

  def display_plan
    plan_key.to_s.humanize
  end

  def display_status
    status.to_s.humanize
  end

  def effective_limits
    Billing::PlanCatalog.limits_for(plan_key).merge(limits_json.to_h.symbolize_keys)
  end

  STATUSES.each do |status_value|
    define_method("#{status_value}?") do
      status.to_s == status_value
    end
  end

  def stripe_customer_id
    provider_customer_id
  end

  def stripe_subscription_id
    provider_subscription_id
  end

  def workspace_accessible?(at: Time.current)
    return false if suspended? || canceled? || past_due? || incomplete?
    return true if active?

    trialing? && (trial_ends_at.blank? || trial_ends_at > at)
  end

  def billing_restricted?(at: Time.current)
    !workspace_accessible?(at: at)
  end

  def trial_days_remaining(at: Time.current)
    return nil if trial_ends_at.blank?

    seconds = trial_ends_at - at
    return 0 if seconds <= 0

    (seconds / 1.day).ceil
  end
end
