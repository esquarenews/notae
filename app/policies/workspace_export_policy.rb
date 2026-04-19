class WorkspaceExportPolicy < ApplicationPolicy
  def create?
    workspace_policy.show?
  end

  def download?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def workspace_policy
    @workspace_policy ||= WorkspacePolicy.new(user, record.workspace)
  end
end
