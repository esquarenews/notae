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
    create?
  end

  def destroy?
    create? && !record.owner?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.joins(:workspace).merge(WorkspacePolicy::Scope.new(user, Workspace).resolve)
    end
  end

  private

  def workspace_membership
    return nil unless user

    @workspace_membership ||= Membership.find_by(user_id: user.id, workspace_id: record.workspace_id)
  end
end
