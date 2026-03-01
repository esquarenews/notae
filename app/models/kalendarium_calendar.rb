class KalendariumCalendar < ApplicationRecord
  SOURCE_KINDS = %w[local provider project].freeze

  belongs_to :workspace
  belongs_to :kalendarium_connection, optional: true
  belongs_to :created_by, class_name: "User"

  has_many :kalendarium_events, dependent: :destroy
  has_one :kalendarium_project, dependent: :nullify

  validates :name, presence: true, length: { maximum: 160 }
  validates :color_hex, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }
  validates :time_zone, presence: true
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validate :time_zone_supported

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :enabled, -> { where(enabled: true) }

  private

  def time_zone_supported
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not supported")
  end
end
