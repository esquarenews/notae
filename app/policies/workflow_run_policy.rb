class WorkflowRunPolicy < ApplicationPolicy
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

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_scope = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      admin_workspace_ids = Membership.where(user_id: user.id, role: %w[admin owner]).select(:workspace_id)
      auditor_workspace_ids = Membership.where(user_id: user.id, role: %w[auditor]).select(:workspace_id)

      own_runs = scope.where(workspace_id: workspace_scope, user_id: user.id)
      admin_runs = scope.where(workspace_id: admin_workspace_ids)
      auditor_runs = scope.where(workspace_id: auditor_workspace_ids)

      own_runs.or(admin_runs).or(auditor_runs)
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
