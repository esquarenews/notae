class DbRowPolicy < ApplicationPolicy
  def show?
    database_policy.show?
  end

  def create?
    database_policy.update?
  end

  def update?
    create?
  end

  def destroy?
    database_policy.destroy?
  end

  def restore?
    database_policy.destroy?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def database_policy
    @database_policy ||= DatabasePolicy.new(user, record.database)
  end
end
