class DatabaseViewPolicy < ApplicationPolicy
  def show?
    database_policy.show?
  end

  def create?
    database_policy.update?
  end

  def update?
    create?
  end

  def set_default?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: accessible_workspace_ids)
    end
  end

  private

  def database_policy
    @database_policy ||= DatabasePolicy.new(user, record.database)
  end
end
