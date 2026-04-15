require "digest"

class MeetingSession < ApplicationRecord
  include PgSearch::Model

  CAPTURE_MODES = %w[online_bot browser_extension in_person_mic upload].freeze
  PROVIDERS = %w[google_meet zoom teams local].freeze
  STATUSES = %w[scheduled joining recording uploading processing summarizing proposing completed failed cancelled].freeze
  ACTIVE_STATUSES = %w[scheduled joining recording uploading processing summarizing proposing].freeze

  belongs_to :workspace
  belongs_to :kalendarium_event, optional: true
  belongs_to :page, optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :updated_by, class_name: "User"

  has_many :meeting_utterances, dependent: :destroy
  has_many :meeting_bot_runs, dependent: :destroy
  has_many :search_chunks, dependent: :destroy
  has_one :latest_meeting_bot_run, -> { order(created_at: :desc) }, class_name: "MeetingBotRun"
  has_many_attached :capture_files

  validates :title, presence: true, length: { maximum: 200 }
  validates :capture_mode, inclusion: { in: CAPTURE_MODES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  pg_search_scope :search_full_text,
                  against: %i[title transcript_text summary_markdown],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  after_commit :enqueue_search_chunk_reindex, on: %i[create update], if: :search_chunk_reindex_required?
  after_commit :remove_search_chunks, on: :destroy

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def processing?
    %w[processing summarizing proposing].include?(status)
  end

  def capture_mode_label
    case capture_mode
    when "browser_extension"
      "Google Meet extension"
    when "in_person_mic"
      "Microphone"
    when "online_bot"
      "Legacy browser bot"
    else
      capture_mode.to_s.humanize
    end
  end

  def transcript_text_from_utterances
    meeting_utterances.ordered.map do |utterance|
      timestamp = self.class.milliseconds_to_clock(utterance.started_ms.to_i)
      speaker = utterance.speaker_name.to_s.presence || utterance.speaker_key.to_s
      "[#{timestamp}] #{speaker}: #{utterance.text.to_s.strip}"
    end.join("\n")
  end

  def self.milliseconds_to_clock(value)
    seconds = [ value.to_i / 1000, 0 ].max
    minutes = seconds / 60
    remaining_seconds = seconds % 60
    format("%02d:%02d", minutes, remaining_seconds)
  end

  def self.normalize_join_url(raw_url)
    value = raw_url.to_s.strip
    return nil if value.blank?
    return value if value.start_with?("https://", "http://")

    nil
  end

  def search_source_text
    action_items_text = Array(action_items_json).filter_map do |item|
      next unless item.is_a?(Hash)

      [
        item["title"].to_s.strip.presence,
        item["owner"].to_s.strip.presence,
        item["due_at"].to_s.strip.presence
      ].compact.join(" ")
    end.join("\n")

    content = [
      title,
      transcript_text,
      summary_markdown,
      action_items_text,
      kalendarium_event&.title,
      page&.title
    ].compact.join("\n").squish
    return "" if transcript_text.to_s.strip.blank? && summary_markdown.to_s.strip.blank? && action_items_text.blank?

    content
  end

  private

  def search_chunk_reindex_required?
    return true if previous_changes.key?("id")

    changed_keys = previous_changes.keys
    (changed_keys & %w[
      title
      transcript_text
      summary_markdown
      action_items_json
      kalendarium_event_id
      page_id
      status
    ]).any?
  end

  def enqueue_search_chunk_reindex
    Search::IndexMeetingSessionJob.perform_later(id)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    Rails.logger.warn("Search index queue unavailable for meeting_session=#{id}: #{error.class}: #{error.message}")
    Search::ChunkIndexingService.index_meeting_session!(meeting_session: self)
  end

  def remove_search_chunks
    Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_MEETING_SESSION, source_id: id)
  end
end
