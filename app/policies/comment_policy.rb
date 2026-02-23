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

      workspace_ids = WorkspacePolicy::Scope.new(user, Workspace).resolve.select(:id)
      visible_page_ids = PagePolicy::Scope.new(user, Page).resolve.select(:id)
      visible_block_ids = BlockPolicy::Scope.new(user, Block).resolve.select(:id)

      scope.where(workspace_id: workspace_ids).where(
        Comment.arel_table[:commentable_type].eq("Page").and(Comment.arel_table[:commentable_id].in(visible_page_ids))
          .or(Comment.arel_table[:commentable_type].eq("Block").and(Comment.arel_table[:commentable_id].in(visible_block_ids)))
      )
    end
  end

  private

  def commentable_show?
    case record.commentable
    when Page
      PagePolicy.new(user, record.commentable).show?
    when Block
      BlockPolicy.new(user, record.commentable).show?
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
    else
      false
    end
  end
end
