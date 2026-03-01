class KalendariumWriteProposal < ApplicationRecord
  PROPOSED_BY_OPTIONS = %w[api ai_assistant].freeze
  OPERATION_OPTIONS = %w[create update delete].freeze
  STATUS_OPTIONS = %w[pending confirmed rejected expired failed].freeze

  belongs_to :workspace
  belongs_to :user
  belongs_to :kalendarium_event, optional: true

  validates :proposed_by, inclusion: { in: PROPOSED_BY_OPTIONS }
  validates :operation, inclusion: { in: OPERATION_OPTIONS }
  validates :status, inclusion: { in: STATUS_OPTIONS }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :pending, -> { where(status: "pending") }
  scope :recent_first, -> { order(created_at: :desc) }

  def confirm!(event: nil)
    update!(
      status: "confirmed",
      applied_at: Time.current,
      rejected_at: nil,
      kalendarium_event: event || kalendarium_event,
      error_message: nil
    )
  end

  def reject!
    update!(status: "rejected", rejected_at: Time.current)
  end
end
