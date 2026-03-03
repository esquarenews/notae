class MeetingBotRun < ApplicationRecord
  STATUSES = %w[queued claimed joining recording uploading finished failed].freeze
  PROVIDERS = %w[google_meet zoom teams].freeze

  belongs_to :meeting_session

  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: %w[queued claimed joining recording uploading]) }
end
