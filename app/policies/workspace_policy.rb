class WorkspacePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    membership.present? && !record.archived?
  end

  def create?
    user.present?
  end

  def update?
    !record.archived? && (membership&.admin? || membership&.owner?)
  end

  def destroy?
    !record.archived? && membership&.owner?
  end

  def join_via_link?
    user.present? && !record.archived? && record.join_link_enabled?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.active.joins(:memberships).where(memberships: { user_id: user.id }).distinct
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= record.memberships.find_by(user_id: user.id)
  end
end
