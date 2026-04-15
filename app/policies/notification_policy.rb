class NotificationPolicy < ApplicationPolicy
  def show?
    user.present? && record.recipient_id == user.id
  end

  def index?
    user.present?
  end

  def mark_read?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.for_recipient(user).where(workspace_id: accessible_workspace_ids)
    end
  end
end
