class KalendariumCalendarPolicy < ApplicationPolicy
  def show?
    return false unless membership

    return true if record.kalendarium_connection.blank?

    KalendariumConnectionPolicy.new(user, record.kalendarium_connection).show?
  end

  def create?
    membership.present? && !membership.guest?
  end

  def update?
    return false unless membership

    if record.kalendarium_connection.present?
      KalendariumConnectionPolicy.new(user, record.kalendarium_connection).update?
    else
      !membership.guest?
    end
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      scope.where(workspace_id: workspace_ids)
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
