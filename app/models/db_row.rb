class DbRow < ApplicationRecord
  include PgSearch::Model

  has_paper_trail

  belongs_to :workspace
  belongs_to :database
  has_many :db_cells, dependent: :destroy

  validates :title, presence: true

  scope :active, -> { where(archived_at: nil) }
  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  pg_search_scope :search_full_text,
                  against: %i[title search_text],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_database
  before_validation :set_search_text

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

  def set_search_text
    flattened = data_json.is_a?(Hash) ? data_json.values.join(" ") : data_json.to_s
    self.search_text = [ title, flattened ].compact.join(" ").strip
  end
end
