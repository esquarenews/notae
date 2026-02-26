class SearchesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def index
    authorize @workspace, :show?
    @query = params[:q].to_s.strip
    @search_results = []
    @ai_answer = nil
    return if @query.blank?

    @search_results = Search::WorkspaceSearchService.new(
      user: current_user,
      workspace: @workspace,
      query: @query
    ).call
    @ai_answer = Search::WorkspaceAnswerService.new(
      user: current_user,
      workspace: @workspace,
      query: @query,
      results: @search_results
    ).call
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
