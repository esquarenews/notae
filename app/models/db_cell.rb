class DbCell < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :db_row
  belongs_to :db_property

  validates :db_property_id, uniqueness: { scope: :db_row_id }
  validate :relations_share_workspace
  validate :property_belongs_to_row_database

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_database, ->(database) { joins(:db_row).where(db_rows: { database_id: database.id }) }

  before_validation :set_workspace_from_row
  after_commit :sync_row_data_cache

  private

  def set_workspace_from_row
    self.workspace = db_row.workspace if db_row.present?
  end

  def relations_share_workspace
    return if workspace_id.blank?

    if db_row.present? && db_row.workspace_id != workspace_id
      errors.add(:db_row_id, "must belong to the same workspace")
    end

    if db_property.present? && db_property.workspace_id != workspace_id
      errors.add(:db_property_id, "must belong to the same workspace")
    end
  end

  def property_belongs_to_row_database
    return if db_row.blank? || db_property.blank?
    return if db_row.database_id == db_property.database_id

    errors.add(:db_property_id, "must belong to the same database as the row")
  end

  def sync_row_data_cache
    row = DbRow.find_by(id: db_row_id)
    row&.sync_data_from_cells!
  end
end
