class DbPropertyPolicy < ApplicationPolicy
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
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      accessible_database_ids = DatabasePolicy::Scope.new(user, Database).resolve.select(:id)
      scope.where(database_id: accessible_database_ids)
    end
  end

  private

  def database_policy
    @database_policy ||= DatabasePolicy.new(user, record.database)
  end
end
