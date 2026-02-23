class PageLinkPolicy < ApplicationPolicy
  def show?
    source_page_policy.show? && target_page_policy.show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      visible_page_ids = PagePolicy::Scope.new(user, Page).resolve.select(:id)
      scope.where(source_page_id: visible_page_ids, target_page_id: visible_page_ids)
    end
  end

  private

  def source_page_policy
    @source_page_policy ||= PagePolicy.new(user, record.source_page)
  end

  def target_page_policy
    @target_page_policy ||= PagePolicy.new(user, record.target_page)
  end
end
