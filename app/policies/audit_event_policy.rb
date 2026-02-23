class AuditEventPolicy < ApplicationPolicy
  def show?
    workspace_membership&.admin_or_owner?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(
        workspace_id: Membership.where(
          user_id: user.id,
          role: [ Membership.roles.fetch("admin"), Membership.roles.fetch("owner") ]
        ).select(:workspace_id)
      )
    end
  end

  private

  def workspace_membership
    return nil unless user

    @workspace_membership ||= Membership.find_by(user_id: user.id, workspace_id: record.workspace_id)
  end
end
