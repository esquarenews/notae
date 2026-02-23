class WorkspacePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    membership.present?
  end

  def create?
    user.present?
  end

  def update?
    membership&.admin? || membership&.owner?
  end

  def destroy?
    membership&.owner?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.joins(:memberships).where(memberships: { user_id: user.id }).distinct
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= record.memberships.find_by(user_id: user.id)
  end
end
