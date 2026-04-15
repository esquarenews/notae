class MeetingBotRunPolicy < ApplicationPolicy
  def show?
    meeting_policy.show?
  end

  def create?
    meeting_policy.create?
  end

  def update?
    meeting_policy.update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.joins(:meeting_session)
           .where(meeting_sessions: { workspace_id: accessible_workspace_ids })
    end
  end

  private

  def meeting_policy
    @meeting_policy ||= MeetingSessionPolicy.new(user, record.meeting_session)
  end
end
