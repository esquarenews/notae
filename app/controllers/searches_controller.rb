class SearchesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def index
    authorize @workspace, :show?
    @query = params[:q].to_s.strip
    @search_results = if @query.present?
      Search::WorkspaceSearchService.new(
        user: current_user,
        workspace: @workspace,
        query: @query
      ).call
    else
      []
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
