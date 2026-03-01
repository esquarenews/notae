class KalendariumConnectionPolicy < ApplicationPolicy
  def show?
    return false unless membership

    record.shared_connection? ? true : record.owner_id == user.id
  end

  def create?
    membership.present? && !membership.guest?
  end

  def update?
    return false unless membership

    if record.shared_connection?
      membership.admin_or_owner?
    else
      record.owner_id == user.id
    end
  end

  def destroy?
    update?
  end

  def sync?
    update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      scope.where(workspace_id: workspace_ids)
           .where(
             scope.arel_table[:owner_type].eq("Workspace")
             .or(
               scope.arel_table[:owner_type].eq("User")
                    .and(scope.arel_table[:owner_id].eq(user.id))
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
