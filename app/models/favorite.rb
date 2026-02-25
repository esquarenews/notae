class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :workspace
  belongs_to :favoritable, polymorphic: true

  validates :favoritable_type, inclusion: { in: %w[Page Database] }
  validates :favoritable_id, uniqueness: { scope: %i[user_id favoritable_type] }
  validate :workspace_matches_favoritable

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :recent, -> { order(created_at: :desc) }

  private

  def workspace_matches_favoritable
    return if workspace_id.blank? || favoritable.blank?
    return if favoritable.workspace_id == workspace_id

    errors.add(:workspace_id, "must match favoritable workspace")
  end
end
