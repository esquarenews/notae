class KalendariumWriteProposalPolicy < ApplicationPolicy
  def show?
    return false unless membership

    record.user_id == user.id || membership.admin_or_owner?
  end

  def create?
    membership.present? && !membership.guest?
  end

  def confirm?
    show?
  end

  def reject?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
           .where(
             scope.arel_table[:user_id].eq(user.id)
             .or(
               scope.arel_table[:workspace_id].in(
                 Membership.where(user_id: user.id, role: [ Membership.roles.fetch("admin"), Membership.roles.fetch("owner") ]).select(:workspace_id)
               )
             )
           )
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= Membership.find_by(user_id: user.id, workspace_id: record.workspace_id)
  end
end
