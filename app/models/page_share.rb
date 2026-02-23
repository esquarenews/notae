class PageShare < ApplicationRecord
  has_paper_trail

  belongs_to :page
  belongs_to :user
  belongs_to :created_by, class_name: "User"

  validates :user_id, uniqueness: { scope: :page_id }
  validate :user_belongs_to_page_workspace

  private

  def user_belongs_to_page_workspace
    return if page.blank? || user.blank?
    return if Membership.exists?(workspace_id: page.workspace_id, user_id: user_id)

    errors.add(:user_id, "must belong to the page workspace")
  end
end
