class KalendariumCalendar < ApplicationRecord
  SOURCE_KINDS = %w[local provider project].freeze
  ICLOUD_WRITABLE_SQL = <<~SQL.squish.freeze
    (
      kalendarium_calendars.read_only = FALSE
      OR (
        kalendarium_calendars.provider = 'icloud_caldav'
        AND kalendarium_calendars.source_kind = 'provider'
        AND COALESCE(kalendarium_calendars.metadata_json ->> 'subscribed', 'false') = 'false'
        AND COALESCE(kalendarium_calendars.metadata_json ->> 'writable', 'true') = 'true'
      )
    )
  SQL

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
  scope :user_writable, -> { where(ICLOUD_WRITABLE_SQL) }

  def user_writable?
    return !read_only? unless provider == "icloud_caldav" && source_kind == "provider"

    metadata = metadata_json.to_h
    return false if ActiveModel::Type::Boolean.new.cast(metadata["subscribed"])

    writable = metadata["writable"]
    return ActiveModel::Type::Boolean.new.cast(writable) unless writable.nil?

    true
  end

  private

  def time_zone_supported
    return if ActiveSupport::TimeZone[time_zone].present?

    errors.add(:time_zone, "is not supported")
  end
end
