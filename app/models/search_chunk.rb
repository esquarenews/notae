require "digest"

class SearchChunk < ApplicationRecord
  SOURCE_PAGE = "page"
  SOURCE_DB_ROW = "db_row"
  SOURCE_KALENDARIUM_EVENT = "kalendarium_event"
  SOURCE_MEETING_SESSION = "meeting_session"
  SOURCE_EPISTULARIUM_MESSAGE = "epistularium_message"
  SOURCE_TYPES = [
    SOURCE_PAGE,
    SOURCE_DB_ROW,
    SOURCE_KALENDARIUM_EVENT,
    SOURCE_MEETING_SESSION,
    SOURCE_EPISTULARIUM_MESSAGE
  ].freeze

  EMBEDDING_MODEL = "text-embedding-3-small"

  belongs_to :workspace
  belongs_to :page, optional: true
  belongs_to :db_row, optional: true
  belongs_to :database, optional: true
  belongs_to :kalendarium_event, optional: true
  belongs_to :meeting_session, optional: true
  belongs_to :epistularium_message, optional: true

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

  def self.reference_column_available?(column_name)
    column_names.include?(column_name.to_s)
  end

  def self.context_preload_associations
    associations = [
      :workspace,
      { page: [ :parent_page, :linked_database ] },
      { database: { linked_page: :parent_page } },
      { db_row: { database: { linked_page: :parent_page } } }
    ]
    associations << :kalendarium_event if reference_column_available?(:kalendarium_event_id)
    associations << :meeting_session if reference_column_available?(:meeting_session_id)
    associations << { epistularium_message: :epistularium_account } if reference_column_available?(:epistularium_message_id)
    associations
  end

  def self.accessible_scope_from(base:, page_ids:, row_ids:, event_ids:, meeting_ids:, message_ids: nil)
    scopes = [
      base.where(page_id: page_ids),
      base.where(db_row_id: row_ids)
    ]
    scopes << base.where(kalendarium_event_id: event_ids) if reference_column_available?(:kalendarium_event_id)
    scopes << base.where(meeting_session_id: meeting_ids) if reference_column_available?(:meeting_session_id)
    scopes << base.where(epistularium_message_id: message_ids) if reference_column_available?(:epistularium_message_id) && message_ids.present?

    scopes.reduce { |combined, relation| combined.or(relation) } || base.none
  end

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
      when SOURCE_EPISTULARIUM_MESSAGE then epistularium_message
      end
    return if record.blank? || !record.respond_to?(:search_source_text)

    Digest::SHA256.hexdigest(record.search_source_text.to_s)
  end

  def set_default_source_content_hash
    self.source_content_hash = content_hash if source_content_hash.blank? && content_hash.present?
  end
end
