class DbCellPolicy < ApplicationPolicy
  def show?
    row_policy.show?
  end

  def create?
    row_policy.update?
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

      scope.where(workspace_id: accessible_workspace_ids)
    end
  end

  private

  def row_policy
    @row_policy ||= DbRowPolicy.new(user, record.db_row)
  end
end
