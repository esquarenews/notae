class TrashController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @query = params[:q].to_s.strip
    @archived_pages = policy_scope(Page).for_workspace(@workspace).archived
    if @query.present?
      @archived_pages = @archived_pages.where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%")
    end
    @archived_pages = @archived_pages.order(updated_at: :desc).limit(100)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
