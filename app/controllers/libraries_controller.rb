class LibrariesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @recent_pages = policy_scope(Page).for_workspace(@workspace).active.order(updated_at: :desc).limit(12)
    @recent_databases = policy_scope(Database).for_workspace(@workspace).order(updated_at: :desc).limit(12)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
