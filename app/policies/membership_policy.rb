class MembershipPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    workspace_membership.present?
  end

  def create?
    workspace_membership&.admin? || workspace_membership&.owner?
  end

  def update?
    return false unless workspace_membership
    return false if record.user_id == user.id

    if workspace_membership.owner?
      !record.owner?
    elsif workspace_membership.admin?
      record.member? || record.guest? || record.auditor? || record.automation_agent?
    else
      false
    end
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: accessible_workspace_ids)
    end
  end

  private

  def workspace_membership
    return nil unless user

    @workspace_membership ||= membership_for_workspace(record.workspace_id)
  end
end
