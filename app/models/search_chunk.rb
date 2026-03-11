require "digest"

class SearchChunk < ApplicationRecord
  SOURCE_PAGE = "page"
  SOURCE_DB_ROW = "db_row"
  SOURCE_KALENDARIUM_EVENT = "kalendarium_event"
  SOURCE_MEETING_SESSION = "meeting_session"
  SOURCE_TYPES = [ SOURCE_PAGE, SOURCE_DB_ROW, SOURCE_KALENDARIUM_EVENT, SOURCE_MEETING_SESSION ].freeze

  EMBEDDING_MODEL = "text-embedding-3-small"

  belongs_to :workspace
  belongs_to :page, optional: true
  belongs_to :db_row, optional: true
  belongs_to :database, optional: true
  belongs_to :kalendarium_event, optional: true
  belongs_to :meeting_session, optional: true

  before_validation :set_default_source_content_hash

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, presence: true
  validates :chunk_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :text, presence: true
  validates :token_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :content_hash, presence: true
  validates :source_content_hash, presence: true, allow_blank: false

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_source, ->(source_type, source_id) { where(source_type: source_type, source_id: source_id) }

  def embedding_vector
    Array(embedding).map(&:to_f)
  end

  def has_embedding?
    embedding_vector.any?
  end

  def provenance_payload
    {
      source_type: source_type,
      source_id: source_id,
      source_uri: source_uri,
      source_title: source_title,
      content_hash: content_hash,
      source_content_hash: source_content_hash,
      metadata: metadata_json.to_h
    }
  end

  def hash_verification_succeeds?
    expected_hash = source_record_content_hash
    return false if expected_hash.blank?

    expected_hash == source_content_hash
  end

  private

  def source_record_content_hash
    record =
      case source_type
      when SOURCE_PAGE then page
      when SOURCE_DB_ROW then db_row
      when SOURCE_KALENDARIUM_EVENT then kalendarium_event
      when SOURCE_MEETING_SESSION then meeting_session
      end
    return if record.blank? || !record.respond_to?(:search_source_text)

    Digest::SHA256.hexdigest(record.search_source_text.to_s)
  end

  def set_default_source_content_hash
    self.source_content_hash = content_hash if source_content_hash.blank? && content_hash.present?
  end
end
