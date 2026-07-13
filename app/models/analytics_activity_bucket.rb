class AnalyticsActivityBucket < ApplicationRecord
  BUCKET_SECONDS = 30
  SURFACES = %w[
    home
    nota
    grid
    ai
    calendar
    mail
    meetings
    search
    settings
    other
  ].freeze
  SURFACE_LABELS = {
    "home" => "Workspace & home",
    "nota" => "Notas",
    "grid" => "Grids",
    "ai" => "Notae AI",
    "calendar" => "Kalendarium",
    "mail" => "Epistularium",
    "meetings" => "Meetings",
    "search" => "Search & library",
    "settings" => "Settings",
    "other" => "Other"
  }.freeze

  belongs_to :user
  belongs_to :workspace, optional: true

  before_validation :assign_sample_id, on: :create

  validates :surface, inclusion: { in: SURFACES }
  validates :bucket_started_at, presence: true
  validates :sample_id,
            presence: true,
            length: { maximum: 80 },
            uniqueness: { scope: [ :user_id, :segment_index ] }
  validates :segment_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :segment_offset_seconds,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than: BUCKET_SECONDS
            }
  validates :duration_seconds,
            numericality: {
              only_integer: true,
              greater_than: 0,
              less_than_or_equal_to: BUCKET_SECONDS
            }
  validate :segment_fits_bucket

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_workspaces, ->(workspaces) { where(workspace_id: Array(workspaces).map { |workspace| workspace.respond_to?(:id) ? workspace.id : workspace }) }
  scope :within, ->(range) { where(bucket_started_at: range) }

  def self.label_for(surface)
    SURFACE_LABELS.fetch(surface.to_s, surface.to_s.humanize)
  end

  private

  def assign_sample_id
    self.sample_id = SecureRandom.uuid if sample_id.blank?
  end

  def segment_fits_bucket
    return unless segment_offset_seconds.is_a?(Numeric) && duration_seconds.is_a?(Numeric)
    return if segment_offset_seconds + duration_seconds <= BUCKET_SECONDS

    errors.add(:duration_seconds, "must end within its wall-clock bucket")
  end
end
