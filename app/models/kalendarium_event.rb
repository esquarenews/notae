class KalendariumEvent < ApplicationRecord
  include PgSearch::Model

  SOURCE_KINDS = %w[local provider].freeze
  STATUSES = %w[confirmed tentative cancelled].freeze
  VISIBILITIES = %w[default private public].freeze

  belongs_to :workspace
  belongs_to :kalendarium_calendar
  belongs_to :kalendarium_project, optional: true
  belongs_to :linked_page, class_name: "Page", optional: true
  belongs_to :linked_db_row, class_name: "DbRow", optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :updated_by, class_name: "User"

  has_many :kalendarium_write_proposals, dependent: :nullify
  has_many :search_chunks, dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }
  validates :starts_at_utc, presence: true
  validates :ends_at_utc, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validate :ends_after_starts
  validate :reminder_offsets_are_valid

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_range, ->(range_start, range_end) { where("starts_at_utc < ? AND ends_at_utc > ?", range_end, range_start) }
  scope :recent_first, -> { order(starts_at_utc: :desc) }

  pg_search_scope :search_full_text,
                  against: %i[title description location],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  after_commit :enqueue_search_chunk_reindex, on: %i[create update]
  after_commit :remove_search_chunks, on: :destroy
  before_validation :normalize_reminder_offsets

  def all_day_range
    starts_at_utc.to_date..ends_at_utc.to_date
  end

  private

  def ends_after_starts
    return if starts_at_utc.blank? || ends_at_utc.blank?
    return if ends_at_utc > starts_at_utc

    errors.add(:ends_at_utc, "must be after start time")
  end

  def reminder_offsets_are_valid
    return if reminder_offsets_minutes.is_a?(Array) && reminder_offsets_minutes.all? { |offset| offset.is_a?(Integer) && offset >= 0 }

    errors.add(:reminder_offsets_minutes, "must be non-negative minute offsets")
  end

  def normalize_reminder_offsets
    self.reminder_offsets_minutes = Array(reminder_offsets_minutes).map { |offset| offset.to_i }.select { |offset| offset >= 0 }.uniq.sort
  end

  def enqueue_search_chunk_reindex
    Search::IndexKalendariumEventJob.perform_later(id)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    Rails.logger.warn("Search index queue unavailable for kalendarium_event=#{id}: #{error.class}: #{error.message}")
    Search::ChunkIndexingService.index_kalendarium_event!(kalendarium_event: self)
  end

  def remove_search_chunks
    Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_KALENDARIUM_EVENT, source_id: id)
  end
end
