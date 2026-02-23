class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page
  before_action :set_commentable
  before_action :set_comment, only: %i[resolve unresolve]

  def create
    @comment = @commentable.comments.new(comment_params)
    @comment.author = current_user
    @comment.workspace = @workspace
    authorize @comment

    if @comment.save
      Comments::ProcessMentionsService.call(comment: @comment)
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Comment added."
    else
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: @comment.errors.full_messages.to_sentence
    end
  end

  def resolve
    authorize @comment, :resolve?
    @comment.resolve!(by: current_user)
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Comment resolved."
  end

  def unresolve
    authorize @comment, :unresolve?
    @comment.unresolve!
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Comment reopened."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])
    authorize @page, :show?
  end

  def set_commentable
    @commentable =
      if params[:block_id].present?
        policy_scope(Block).for_page(@page).find(params[:block_id])
      else
        @page
      end
  end

  def set_comment
    @comment = @commentable.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:body)
  end
end
