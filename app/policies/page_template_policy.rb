class PageTemplatePolicy < ApplicationPolicy
  def create?
    page_policy.show? && page_policy.create?
  end

  def instantiate?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(workspace_id: WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id))
    end
  end

  private

  def page_policy
    @page_policy ||= PagePolicy.new(user, record.page)
  end
end
