class AgentActionPolicy < ApplicationPolicy
  def index?
    membership.present? && !membership.guest?
  end

  def show?
    return false unless membership.present? && !membership.guest?
    return true if membership.audit_reviewer?

    record.user_id == user.id
  end

  def create?
    membership&.can_author_agent_actions?
  end

  def update?
    return false unless membership&.can_author_agent_actions?

    record.editable? && (record.user_id == user.id || membership.admin_or_owner?)
  end

  def approve?
    membership&.admin_or_owner? && record.approvable?
  end

  def request_changes?
    membership&.admin_or_owner? && record.request_changes_allowed?
  end

  def reject?
    membership&.admin_or_owner? && record.pending?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_scope = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      admin_workspace_ids = Membership.where(
        user_id: user.id,
        role: %w[admin owner]
      ).select(:workspace_id)
      auditor_workspace_ids = Membership.where(
        user_id: user.id,
        role: %w[auditor]
      ).select(:workspace_id)

      own_actions = scope.where(workspace_id: workspace_scope, user_id: user.id)
      admin_actions = scope.where(workspace_id: admin_workspace_ids)
      auditor_actions = scope.where(workspace_id: auditor_workspace_ids)

      own_actions.or(admin_actions).or(auditor_actions)
    end
  end

  private

  def membership
    return nil unless user

    workspace_id = if record.is_a?(Class)
      nil
    else
      record.workspace_id || record.workspace&.id
    end

    @membership ||= membership_for_workspace(workspace_id)
  end
end
