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

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      visible_page_ids = PagePolicy::Scope.new(user, Page).resolve.pluck(:id)
      visible_database_ids = DatabasePolicy::Scope.new(user, Database).resolve.pluck(:id)

      favorites = scope.where(user_id: user.id, workspace_id: workspace_ids)
      table = Favorite.arel_table
      page_clause = table[:favoritable_type].eq("Page").and(table[:favoritable_id].in(visible_page_ids))
      database_clause = table[:favoritable_type].eq("Database").and(table[:favoritable_id].in(visible_database_ids))

      favorites.where(page_clause.or(database_clause))
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

    Membership.find_by(user_id: user.id, workspace_id: workspace_id)
  end
end
