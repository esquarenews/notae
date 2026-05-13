class WorkspaceExportPolicy < ApplicationPolicy
  def create?
    workspace_policy.update?
  end

  def download?
    workspace_policy.update? || record.requested_by_id == user&.id
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope
        .where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
        .where(requested_by_id: user.id)
    end
  end

  private

  def workspace_policy
    @workspace_policy ||= WorkspacePolicy.new(user, record.workspace)
  end
end
