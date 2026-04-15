class KalendariumCalendarPolicy < ApplicationPolicy
  def show?
    return false unless membership

    return true if record.kalendarium_connection.blank?

    KalendariumConnectionPolicy.new(user, record.kalendarium_connection).show?
  end

  def create?
    membership&.content_editor?
  end

  def update?
    return false unless membership

    if record.kalendarium_connection.present?
      KalendariumConnectionPolicy.new(user, record.kalendarium_connection).update?
    else
      membership.content_editor?
    end
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: accessible_workspace_ids)
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
