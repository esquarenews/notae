class DatabasePolicy < ApplicationPolicy
  def show?
    return false unless membership
    return true if membership.admin_or_owner?

    case record.permission_mode
    when "shared_to_workspace"
      true
    when "private_database"
      record.created_by_id == user.id
    when "specific_users"
      record.visible_to_specific_user?(user)
    else
      false
    end
  end

  def create?
    membership&.content_editor?
  end

  def update?
    return false unless create?
    return true unless record.respond_to?(:locked?) && record.locked?

    membership&.admin_or_owner?
  end

  def destroy?
    membership&.admin_or_owner?
  end

  def archive?
    destroy?
  end

  def restore?
    destroy?
  end

  def permissions?
    return false unless membership

    membership.admin_or_owner? || record.created_by_id == user.id
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope
        .where(workspace_id: accessible_workspace_ids)
        .left_joins(:database_shares)
        .where(
          Database.arel_table[:workspace_id].in(admin_workspace_ids)
            .or(Database.arel_table[:permission_mode].eq(Database.permission_modes.fetch("shared_to_workspace")))
            .or(Database.arel_table[:created_by_id].eq(user.id))
            .or(DatabaseShare.arel_table[:user_id].eq(user.id))
        )
        .distinct
    end
  end

  private

  def membership
    return nil unless user

    @membership ||= membership_for_workspace(record.workspace_id)
  end
end
