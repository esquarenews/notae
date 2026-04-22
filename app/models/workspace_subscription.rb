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
  STATUSES = [ STATUS_TRIALING, STATUS_ACTIVE, STATUS_PAST_DUE, STATUS_CANCELED, STATUS_SUSPENDED ].freeze

  PROVIDER_FAT_ZEBRA = "fat_zebra".freeze
  PROVIDERS = [ PROVIDER_FAT_ZEBRA ].freeze

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
end
