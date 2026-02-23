class AuditEvent < ApplicationRecord
  ACTIONS = %w[share role_change delete].freeze

  belongs_to :workspace
  belongs_to :actor, class_name: "User"
  belongs_to :auditable, polymorphic: true, optional: true

  validates :action, presence: true, inclusion: { in: ACTIONS }

  scope :recent_first, -> { order(created_at: :desc) }
end
