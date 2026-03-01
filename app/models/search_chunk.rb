class SearchChunk < ApplicationRecord
  SOURCE_PAGE = "page"
  SOURCE_DB_ROW = "db_row"
  SOURCE_KALENDARIUM_EVENT = "kalendarium_event"
  SOURCE_TYPES = [ SOURCE_PAGE, SOURCE_DB_ROW, SOURCE_KALENDARIUM_EVENT ].freeze

  EMBEDDING_MODEL = "text-embedding-3-small"

  belongs_to :workspace
  belongs_to :page, optional: true
  belongs_to :db_row, optional: true
  belongs_to :database, optional: true
  belongs_to :kalendarium_event, optional: true

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :source_id, presence: true
  validates :chunk_index, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :text, presence: true
  validates :token_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :content_hash, presence: true

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_source, ->(source_type, source_id) { where(source_type: source_type, source_id: source_id) }

  def embedding_vector
    Array(embedding).map(&:to_f)
  end

  def has_embedding?
    embedding_vector.any?
  end
end
