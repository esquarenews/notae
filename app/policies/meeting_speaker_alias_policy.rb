class MeetingSpeakerAliasPolicy < ApplicationPolicy
  def show?
    membership.present?
  end

  def create?
    membership&.content_editor?
  end

  def update?
    create?
  end

  def destroy?
    create?
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
