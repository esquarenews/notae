class BlockPolicy < ApplicationPolicy
  def show?
    page_policy.show?
  end

  def create?
    page_policy.update?
  end

  def update?
    create?
  end

  def reorder?
    create?
  end

  def attach?
    update?
  end

  def download?
    show?
  end

  def archive?
    create?
  end

  def restore?
    create?
  end

  def command?
    update?
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
