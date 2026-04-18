class ApiTokenAuditEvent < ApplicationRecord
  EVENT_TYPES = %w[issued revoked allowed scope_denied].freeze

  belongs_to :api_token
  belongs_to :user
  belongs_to :workspace, optional: true

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :recent_first, -> { order(created_at: :desc) }
end
