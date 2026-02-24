class PageExportPolicy < ApplicationPolicy
  def create?
    page_policy.show?
  end

  def download?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(page_id: PagePolicy::Scope.new(user, Page).resolve.select(:id))
    end
  end

  private

  def page_policy
    @page_policy ||= PagePolicy.new(user, record.page)
  end
end
