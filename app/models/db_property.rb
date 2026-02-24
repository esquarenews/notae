class DbProperty < ApplicationRecord
  POSITION_GAP = 1024

  has_paper_trail

  attribute :property_type, :integer, default: 0
  enum :property_type, { text: 0, number: 1, date: 2, checkbox: 3, select: 4 }, default: :text, scopes: false

  belongs_to :workspace
  belongs_to :database

  has_many :db_cells, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :database_id, case_sensitive: false }
  validates :position, numericality: { greater_than: 0, only_integer: true }

  scope :ordered, -> { order(:position, :created_at) }
  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :set_workspace_from_database
  before_validation :set_initial_position, on: :create

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
end
