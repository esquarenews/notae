class WorkspacePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    membership.present? && !record.archived? && !record.suspended? && subscription_accessible?
  end

  def manage_billing?
    membership&.admin_or_owner? && !record.archived? && !record.suspended?
  end

  def create?
    user.present?
  end

  def update?
    !record.archived? && !record.suspended? && subscription_accessible? && (membership&.admin? || membership&.owner?)
  end

  def destroy?
    !record.archived? && !record.suspended? && subscription_accessible? && membership&.owner?
  end

  def join_via_link?
    user.present? && !record.archived? && subscription_accessible? && record.join_link_enabled?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.active.where(suspended_at: nil).joins(:memberships).where(memberships: { user_id: user.id }).distinct
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.id)
  end

  def subscription_accessible?
    subscription = record.workspace_subscription
    subscription.blank? || subscription.workspace_accessible?
  end
end
