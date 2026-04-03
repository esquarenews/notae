class WorkspaceCoverBrowserController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def unsplash
    authorize @workspace, :show?

    client = Unsplash::Client.new
    page = params[:page].presence&.to_i || 1
    per_page = params[:per_page].presence&.to_i || Unsplash::Client::DEFAULT_PER_PAGE
    query = params[:q].to_s.strip

    result =
      if query.present?
        client.search_photos(query:, page:, per_page:)
      else
        client.list_photos(page:, per_page:)
      end

    render json: result, status: :ok
  rescue Unsplash::Client::Error => error
    render json: { error: error.message }, status: :service_unavailable
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
