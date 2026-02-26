class DatabaseView < ApplicationRecord
  has_paper_trail

  attribute :view_type, :integer, default: 0
  enum :view_type, { table: 0, board: 1, calendar: 2, list: 3, gallery: 4 }, default: :table, scopes: false

  belongs_to :workspace
  belongs_to :database
  belongs_to :created_by, class_name: "User"

  validates :name, presence: true, uniqueness: { scope: :database_id, case_sensitive: false }

  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :ordered, -> { order(default: :desc, created_at: :asc) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :set_workspace_from_database

  def set_as_default!
    transaction do
      self.class.for_database(database).where.not(id: id).update_all(default: false, updated_at: Time.current)
      update!(default: true)
    end
  end

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
  end
end
