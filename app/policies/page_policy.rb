class PagePolicy < ApplicationPolicy
  def show?
    return false unless membership
    return true if membership.admin_or_owner?

    case record.permission_mode
    when "shared_to_workspace"
      true
    when "private_page"
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

  def archive?
    membership&.admin_or_owner?
  end

  def restore?
    archive?
  end

  def destroy?
    archive?
  end

  def permissions?
    return false unless membership

    membership.admin_or_owner? || record.created_by_id == user.id
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      admin_workspace_ids = Membership.where(
        user_id: user.id,
        role: [ Membership.roles.fetch("admin"), Membership.roles.fetch("owner") ]
      ).select(:workspace_id)

      scope
        .where(workspace_id: workspace_ids)
        .left_joins(:page_shares)
        .where(
          Page.arel_table[:workspace_id].in(admin_workspace_ids)
            .or(Page.arel_table[:permission_mode].eq(Page.permission_modes.fetch("shared_to_workspace")))
            .or(Page.arel_table[:created_by_id].eq(user.id))
            .or(PageShare.arel_table[:user_id].eq(user.id))
        )
        .distinct
    end
  end

  private

  def workspace_for_record
    record.respond_to?(:workspace_id) ? record.workspace_id : record.workspace&.id
  end

  def membership
    return nil unless user && workspace_for_record

    @membership ||= membership_for_workspace(workspace_for_record)
  end
end
