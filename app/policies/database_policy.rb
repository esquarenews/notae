class DatabasePolicy < ApplicationPolicy
  def show?
    membership.present?
  end

  def create?
    membership.present? && !membership.guest?
  end

  def update?
    return false unless create?
    return true unless record.respond_to?(:locked?) && record.locked?

    membership&.admin_or_owner?
  end

  def destroy?
    membership&.admin_or_owner?
  end

  def archive?
    destroy?
  end

  def restore?
    destroy?
  end

  def permissions?
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
