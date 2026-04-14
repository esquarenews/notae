class DatabaseTemplate < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :database, optional: true
  belongs_to :created_by, class_name: "User"

  validates :name, presence: true, uniqueness: { scope: :workspace_id, case_sensitive: false }
  validates :snapshot_json, presence: true

  before_validation :set_workspace_from_database

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
  end
end
