class Database < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  has_many :db_properties, -> { order(:position, :created_at) }, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :database_views, dependent: :destroy
  has_many :favorites, as: :favoritable, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :workspace_id }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
end
