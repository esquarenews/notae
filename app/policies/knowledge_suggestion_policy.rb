class KnowledgeSuggestionPolicy < ApplicationPolicy
  def show?
    same_workspace_membership? && own_record?
  end

  def dismiss?
    show?
  end

  def convert_to_task?
    show?
  end

  def convert_to_nota?
    show?
  end

  def refresh?
    same_workspace_membership?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      scope.where(user_id: user.id, workspace_id: workspace_ids)
    end
  end

  private

  def same_workspace_membership?
    membership_for_workspace(record.workspace_id).present?
  end

  def own_record?
    record.user_id == user.id
  end
end
