class Membership < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :user

  enum :role, { member: 0, admin: 1, owner: 2, guest: 3 }, default: :member

  validates :user_id, uniqueness: { scope: :workspace_id }

  def admin_or_owner?
    admin? || owner?
  end
end
