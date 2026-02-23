class DatabasePolicy < ApplicationPolicy
  def show?
    membership.present?
  end

  def create?
    membership.present? && !membership.guest?
  end

  def update?
    create?
  end

  def destroy?
    membership&.admin_or_owner?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= Membership.find_by(user_id: user.id, workspace_id: record.workspace_id)
  end
end
