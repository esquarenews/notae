class EpistulariumMessagePolicy < ApplicationPolicy
  def show?
    return false unless membership

    record.epistularium_account.shared_account? ? true : record.epistularium_account.owner_id == user.id
  end

  def suggest?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.joins(:epistularium_account)
           .where(workspace_id: accessible_workspace_ids)
           .where(
             EpistulariumAccount.arel_table[:owner_type].eq("Workspace")
             .or(
               EpistulariumAccount.arel_table[:owner_type].eq("User")
                                 .and(EpistulariumAccount.arel_table[:owner_id].eq(user.id))
             )
           )
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
