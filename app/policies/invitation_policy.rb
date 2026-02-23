class InvitationPolicy < ApplicationPolicy
  def show?
    true
  end

  def create?
    return false unless user

    workspace_membership&.admin_or_owner?
  end

  def accept?
    return false unless user

    user.email.casecmp(record.email).zero?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def workspace_membership
    @workspace_membership ||= Membership.find_by(user_id: user.id, workspace_id: record.workspace_id)
  end
end
