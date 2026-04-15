class FavoritePolicy < ApplicationPolicy
  def create?
    membership.present? && favoritable_visible?
  end

  def destroy?
    membership.present?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      visible_page_ids = PagePolicy::Scope.new(user, Page).resolve.select(:id)
      visible_database_ids = DatabasePolicy::Scope.new(user, Database).resolve.select(:id)

      favorites = scope.where(user_id: user.id, workspace_id: accessible_workspace_ids)
      page_favorites = favorites.where(favoritable_type: "Page", favoritable_id: visible_page_ids)
      database_favorites = favorites.where(favoritable_type: "Database", favoritable_id: visible_database_ids)

      page_favorites.or(database_favorites)
    end
  end

  private

  def favoritable_visible?
    case favoritable
    when Page
      PagePolicy.new(user, favoritable).show?
    when Database
      DatabasePolicy.new(user, favoritable).show?
    else
      false
    end
  end

  def favoritable
    return nil unless record.respond_to?(:favoritable)

    record.favoritable
  end

  def workspace_id
    return nil unless record.respond_to?(:workspace_id)

    record.workspace_id || favoritable&.workspace_id
  end

  def membership
    return nil unless user && workspace_id

    membership_for_workspace(workspace_id)
  end
end
