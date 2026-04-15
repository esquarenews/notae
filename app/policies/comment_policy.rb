class CommentPolicy < ApplicationPolicy
  def show?
    commentable_show?
  end

  def create?
    commentable_show? && commentable_update?
  end

  def resolve?
    commentable_show? && commentable_update?
  end

  def unresolve?
    resolve?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      visible_page_ids = PagePolicy::Scope.new(user, Page).resolve.select(:id)
      visible_block_ids = BlockPolicy::Scope.new(user, Block).resolve.select(:id)
      visible_database_ids = DatabasePolicy::Scope.new(user, Database).resolve.select(:id)

      scoped = scope.where(workspace_id: accessible_workspace_ids)
      page_visible = scoped.where(commentable_type: "Page", commentable_id: visible_page_ids)
      block_visible = scoped.where(commentable_type: "Block", commentable_id: visible_block_ids)
      database_visible = scoped.where(commentable_type: "Database", commentable_id: visible_database_ids)

      page_visible.or(block_visible).or(database_visible)
    end
  end

  private

  def commentable_show?
    case record.commentable
    when Page
      PagePolicy.new(user, record.commentable).show?
    when Block
      BlockPolicy.new(user, record.commentable).show?
    when Database
      DatabasePolicy.new(user, record.commentable).show?
    else
      false
    end
  end

  def commentable_update?
    case record.commentable
    when Page
      PagePolicy.new(user, record.commentable).update?
    when Block
      BlockPolicy.new(user, record.commentable).update?
    when Database
      DatabasePolicy.new(user, record.commentable).update?
    else
      false
    end
  end
end
