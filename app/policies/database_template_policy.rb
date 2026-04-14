class DatabaseTemplatePolicy < ApplicationPolicy
  def create?
    membership_for_workspace(record.workspace_id)&.content_editor? && (record.database.blank? || source_database_policy.show?)
  end

  def apply?
    membership_for_workspace(record.workspace_id)&.content_editor?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def source_database_policy
    @source_database_policy ||= DatabasePolicy.new(user, record.database)
  end
end
