class AuditEventPolicy < ApplicationPolicy
  def show?
    workspace_membership&.audit_reviewer?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(
        workspace_id: Membership.where(
          user_id: user.id,
          role: [ Membership.roles.fetch("admin"), Membership.roles.fetch("owner"), Membership.roles.fetch("auditor") ]
        ).select(:workspace_id)
      )
    end
  end

  private

  def workspace_membership
    return nil unless user

    @workspace_membership ||= membership_for_workspace(record.workspace_id)
  end
end
