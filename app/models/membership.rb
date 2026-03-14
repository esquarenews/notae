class Membership < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :user

  enum :role, {
    member: 0,
    admin: 1,
    owner: 2,
    guest: 3,
    auditor: 4,
    automation_agent: 5
  }, default: :member

  validates :user_id, uniqueness: { scope: :workspace_id }

  def admin_or_owner?
    admin? || owner?
  end

  def read_only?
    guest? || auditor?
  end

  def content_editor?
    member? || admin? || owner?
  end

  def can_author_agent_actions?
    content_editor? || automation_agent?
  end

  def audit_reviewer?
    admin_or_owner? || auditor?
  end
end
