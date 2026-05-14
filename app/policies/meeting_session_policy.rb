class MeetingSessionPolicy < ApplicationPolicy
  def show?
    membership.present? && record.created_by_id == user.id
  end

  def create?
    membership&.content_editor?
  end

  def start?
    create?
  end

  def stop?
    create?
  end

  def reprocess?
    create?
  end

  def update?
    create?
  end

  def speakers?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: accessible_workspace_ids, created_by_id: user.id)
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
