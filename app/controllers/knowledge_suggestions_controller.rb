class KnowledgeSuggestionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_knowledge_suggestion, only: %i[show dismiss convert_to_task convert_to_nota refresh]

  def show
    authorize @knowledge_suggestion, :show?
    @knowledge_task_databases = knowledge_task_databases_for(@workspace)
  end

  def dismiss
    authorize @knowledge_suggestion, :dismiss?
    @knowledge_suggestion.dismiss!
    redirect_back fallback_location: workspace_path(@workspace.slug), notice: "Suggestion dismissed."
  end

  def refresh
    authorize @knowledge_suggestion, :refresh?

    kind = @knowledge_suggestion.kind
    @knowledge_suggestion.dismiss! if @knowledge_suggestion.status == KnowledgeSuggestion::STATUS_ACTIVE
    Search::PersistKnowledgeSuggestionService.new(user: current_user, workspace: @workspace, kind: kind, force: true).call

    redirect_back fallback_location: workspace_path(@workspace.slug), notice: "Suggestion refreshed."
  end

  def convert_to_task
    authorize @knowledge_suggestion, :convert_to_task?

    database = policy_scope(Database).for_workspace(@workspace).active.find(task_conversion_params[:database_id])
    materializer = Search::KnowledgeSuggestionMaterializerService.new(suggestion: @knowledge_suggestion, actor: current_user)
    row = materializer.create_task!(database: database, task_index: task_conversion_params[:task_index])

    redirect_back fallback_location: database_path(workspace_slug: @workspace.slug, id: database.id, anchor: "row_#{row.id}"), notice: "Suggestion added as a task."
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: workspace_path(@workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def convert_to_nota
    authorize @knowledge_suggestion, :convert_to_nota?

    page = Search::KnowledgeSuggestionMaterializerService.new(suggestion: @knowledge_suggestion, actor: current_user).create_nota!
    redirect_to page_path(workspace_slug: @workspace.slug, id: page.id), notice: "Suggestion converted to a Nota."
  rescue ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: workspace_path(@workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_knowledge_suggestion
    @knowledge_suggestion = policy_scope(KnowledgeSuggestion).for_workspace(@workspace).find(params[:id])
  end

  def task_conversion_params
    params.fetch(:knowledge_suggestion, {}).permit(:database_id, :task_index)
  end
end
