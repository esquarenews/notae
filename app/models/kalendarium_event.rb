require "uri"

class KalendariumEvent < ApplicationRecord
  include PgSearch::Model

  SOURCE_KINDS = %w[local provider].freeze
  STATUSES = %w[confirmed tentative cancelled].freeze
  VISIBILITIES = %w[default private public].freeze
  SEARCH_REINDEX_CHANGE_KEYS = %w[
    title
    description
    location
    kalendarium_project_id
    linked_page_id
    linked_db_row_id
  ].freeze

  belongs_to :workspace
  belongs_to :kalendarium_calendar
  belongs_to :kalendarium_project, optional: true
  belongs_to :linked_page, class_name: "Page", optional: true
  belongs_to :linked_db_row, class_name: "DbRow", optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :updated_by, class_name: "User"

  has_many :kalendarium_write_proposals, dependent: :nullify
  has_many :search_chunks, dependent: :destroy
  has_many :meeting_sessions, dependent: :nullify

  validates :title, presence: true, length: { maximum: 200 }
  validates :starts_at_utc, presence: true
  validates :ends_at_utc, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validate :ends_after_starts
  validate :reminder_offsets_are_valid
  validates :meeting_capture_enabled, inclusion: { in: [ true, false ] }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_range, ->(range_start, range_end) { where("starts_at_utc < ? AND ends_at_utc > ?", range_end, range_start) }
  scope :recent_first, -> { order(starts_at_utc: :desc) }

  pg_search_scope :search_full_text,
                  against: %i[title description location],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  after_commit :enqueue_search_chunk_reindex, on: %i[create update], if: :search_chunk_reindex_required?
  after_commit :remove_search_chunks, on: :destroy
  before_validation :normalize_reminder_offsets

  def all_day_range
    starts_at_utc.to_date..ends_at_utc.to_date
  end

  def meeting_join_url
    raw = metadata_json.to_h["meeting_join_url"].to_s.strip
    return raw if valid_http_url?(raw)

    nil
  end

  def invitees
    Array(metadata_json.to_h["invitees"]).filter_map do |raw_invitee|
      next unless raw_invitee.is_a?(Hash)

      email = raw_invitee["email"].to_s.strip.presence
      name = raw_invitee["name"].to_s.strip.presence
      status = raw_invitee["status"].to_s.strip.presence
      next if email.blank? && name.blank?

      {
        "email" => email,
        "name" => name,
        "status" => status
      }.compact
    end
  end

  def latest_meeting_session
    meeting_sessions.order(created_at: :desc).first
  end

  private

  def valid_http_url?(raw_url)
    uri = URI.parse(raw_url.to_s)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

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

  def search_chunk_reindex_required?
    return true if previous_changes.key?("id")

    (previous_changes.keys & SEARCH_REINDEX_CHANGE_KEYS).any?
  end
end
