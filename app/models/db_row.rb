class DbRow < ApplicationRecord
  include PgSearch::Model

  POSITION_GAP = 1024

  has_paper_trail

  belongs_to :workspace
  belongs_to :database
  belongs_to :linked_page, class_name: "Page", optional: true
  has_many :db_cells, dependent: :destroy
  has_many :search_chunks, dependent: :destroy

  validates :title, presence: true
  validates :position, numericality: { greater_than: 0, only_integer: true }
  validate :linked_page_workspace_matches

  scope :active, -> { where(archived_at: nil) }
  scope :ordered, -> { order(:position, :created_at) }
  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  pg_search_scope :search_full_text,
                  against: %i[title search_text],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_database
  before_validation :set_initial_position, on: :create
  before_validation :set_search_text
  after_commit :enqueue_search_chunk_reindex, on: %i[create update]
  after_commit :remove_search_chunks, on: :destroy

  def sync_data_from_cells!
    serialized_data = db_cells.includes(:db_property).to_a.sort_by { |cell| [ cell.db_property.position, cell.db_property.created_at ] }
                             .each_with_object({}) do |cell, data|
      key = cell.db_property.name.to_s.strip
      next if key.blank?

      data[key] = cell.value_text.to_s
    end

    update!(data_json: serialized_data)
  end

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
  end

  def set_initial_position
    return if database.blank?
    return if position.present? && position != POSITION_GAP

    sibling_max = self.class.for_database(database).maximum(:position) || 0
    self.position = sibling_max + POSITION_GAP
  end

  def set_search_text
    flattened = data_json.is_a?(Hash) ? data_json.values.join(" ") : data_json.to_s
    self.search_text = [ title, flattened ].compact.join(" ").strip
  end

  def linked_page_workspace_matches
    return if linked_page.blank?
    return if linked_page.workspace_id == workspace_id

    errors.add(:linked_page_id, "must belong to the same workspace")
  end

  def enqueue_search_chunk_reindex
    Search::IndexDbRowJob.perform_later(id)
  end

  def remove_search_chunks
    Search::ChunkIndexingService.delete_source!(source_type: SearchChunk::SOURCE_DB_ROW, source_id: id)
  end
end
