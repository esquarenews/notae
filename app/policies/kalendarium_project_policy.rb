class KalendariumProjectPolicy < ApplicationPolicy
  def show?
    membership.present?
  end

  def create?
    membership.present? && !membership.guest?
  end

  def update?
    create?
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

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
