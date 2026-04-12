class DatabaseCommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_comment, only: %i[resolve unresolve]

  def create
    @comment = @database.comments.new(comment_params)
    @comment.author = current_user
    @comment.workspace = @workspace
    authorize @comment

    if @comment.save
      Comments::ProcessMentionsService.call(comment: @comment)
      redirect_to database_redirect_path, notice: "Comment added."
    else
      redirect_to database_redirect_path, alert: @comment.errors.full_messages.to_sentence
    end
  end

  def resolve
    authorize @comment, :resolve?
    @comment.resolve!(by: current_user)
    redirect_to database_redirect_path, notice: "Comment resolved."
  end

  def unresolve
    authorize @comment, :unresolve?
    @comment.unresolve!
    redirect_to database_redirect_path, notice: "Comment reopened."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
    authorize @database, :show?
  end

  def set_comment
    @comment = @database.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:body)
  end

  def database_redirect_path
    preserved_keys = %i[
      view_id month sort_property_id sort_direction filter_property_id filter_value filter_operator
      split_panel split_page_id split_source split_row_id task_row_id
    ]
    preserved_params = params.permit(*preserved_keys).to_h.compact

    database_path(
      {
        workspace_slug: @workspace.slug,
        id: @database.id,
        anchor: "database-comments-menu"
      }.merge(preserved_params)
    )
  end
end
