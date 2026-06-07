class StripeWebhookEvent < ApplicationRecord
  STATUS_RECEIVED = "received".freeze
  STATUS_PROCESSED = "processed".freeze
  STATUS_IGNORED = "ignored".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_RECEIVED, STATUS_PROCESSED, STATUS_IGNORED, STATUS_FAILED ].freeze

  validates :provider_event_id, presence: true, uniqueness: true
  validates :event_name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def processed?
    status == STATUS_PROCESSED
  end

  def failed?
    status == STATUS_FAILED
  end
end
