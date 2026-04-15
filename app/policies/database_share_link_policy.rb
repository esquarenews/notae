class DatabaseShareLinkPolicy < ApplicationPolicy
  def create?
    database_policy.permissions?
  end

  def destroy?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      manageable_database_ids = Database.where(workspace_id: admin_workspace_ids).select(:id)

      scope.where(database_id: manageable_database_ids)
    end
  end

  private

  def database_policy
    @database_policy ||= DatabasePolicy.new(user, record.database)
  end
end
