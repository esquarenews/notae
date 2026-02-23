class DbRow < ApplicationRecord
  include PgSearch::Model

  has_paper_trail

  belongs_to :workspace
  belongs_to :database

  validates :title, presence: true

  scope :active, -> { where(archived_at: nil) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  pg_search_scope :search_full_text,
                  against: %i[title search_text],
                  using: {
                    tsearch: { prefix: true },
                    trigram: {}
                  }

  before_validation :set_workspace_from_database
  before_validation :set_search_text

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
  end

  def set_search_text
    flattened = data_json.is_a?(Hash) ? data_json.values.join(" ") : data_json.to_s
    self.search_text = [ title, flattened ].compact.join(" ").strip
  end
end
