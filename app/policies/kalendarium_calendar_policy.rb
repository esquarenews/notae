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

      accessible_connection_ids = KalendariumConnectionPolicy::Scope
                                  .new(user, KalendariumConnection)
                                  .resolve
                                  .select(:id)
      workspace_calendars = scope.where(workspace_id: accessible_workspace_ids)

      workspace_calendars
        .where(kalendarium_connection_id: nil)
        .or(workspace_calendars.where(kalendarium_connection_id: accessible_connection_ids))
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
