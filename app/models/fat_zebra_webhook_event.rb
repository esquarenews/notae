class FatZebraWebhookEvent < ApplicationRecord
  STATUS_RECEIVED = "received".freeze
  STATUS_PROCESSED = "processed".freeze
  STATUS_IGNORED = "ignored".freeze
  STATUS_FAILED = "failed".freeze
  STATUSES = [ STATUS_RECEIVED, STATUS_PROCESSED, STATUS_IGNORED, STATUS_FAILED ].freeze

  validates :event_name, presence: true
  validates :provider_event_id, presence: true, uniqueness: true
  validates :raw_body_sha256, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  def processed?
    status == STATUS_PROCESSED
  end

  def ignored?
    status == STATUS_IGNORED
  end

  def failed?
    status == STATUS_FAILED
  end
end
