class KalendariumEventPolicy < ApplicationPolicy
  def show?
    calendar_policy.show?
  end

  def create?
    calendar_policy.update? && !record.kalendarium_calendar.read_only?
  end

  def update?
    create?
  end

  def destroy?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def calendar_policy
    @calendar_policy ||= KalendariumCalendarPolicy.new(user, record.kalendarium_calendar)
  end
end
