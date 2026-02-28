class DatabaseShare < ApplicationRecord
  has_paper_trail

  belongs_to :database
  belongs_to :user
  belongs_to :created_by, class_name: "User"

  validates :user_id, uniqueness: { scope: :database_id }
  validate :user_belongs_to_database_workspace

  private

  def user_belongs_to_database_workspace
    return if database.blank? || user.blank?
    return if Membership.exists?(workspace_id: database.workspace_id, user_id: user_id)

    errors.add(:user_id, "must belong to the database workspace")
  end
end
