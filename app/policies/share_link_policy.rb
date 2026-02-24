class ShareLinkPolicy < ApplicationPolicy
  def create?
    page_policy.permissions?
  end

  def destroy?
    create?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      admin_workspace_ids = Membership.where(
        user_id: user.id,
        role: [ Membership.roles.fetch("admin"), Membership.roles.fetch("owner") ]
      ).select(:workspace_id)

      manageable_page_ids = Page.where(
        Page.arel_table[:workspace_id].in(admin_workspace_ids)
          .or(Page.arel_table[:created_by_id].eq(user.id))
      ).select(:id)

      scope.where(page_id: manageable_page_ids)
    end
  end

  private

  def page_policy
    @page_policy ||= PagePolicy.new(user, record.page)
  end
end
