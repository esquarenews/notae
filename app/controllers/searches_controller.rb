class SearchesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def index
    authorize @workspace, :show?
    @query = params[:q].to_s.strip
    @search_results = []
    @ai_answer = nil
    @ai_answer_notice = nil
    return if @query.blank?

    @search_results = Search::WorkspaceSearchService.new(
      user: current_user,
      workspace: @workspace,
      query: @query
    ).call
    answer_service = Search::WorkspaceAnswerService.new(
      user: current_user,
      workspace: @workspace,
      query: @query,
      results: @search_results
    )
    @ai_answer = answer_service.call
    @ai_answer_notice = ai_answer_notice_for(answer_service.unavailable_reason)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def ai_answer_notice_for(reason)
    case reason
    when :rate_limited
      "AI summary is temporarily rate-limited. Try again in a minute."
    when :budget_exceeded
      "AI summary is temporarily unavailable because the daily budget has been reached."
    else
      nil
    end
  end
end
