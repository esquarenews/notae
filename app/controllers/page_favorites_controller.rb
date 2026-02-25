class PageFavoritesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page

  def create
    favorite = Favorite.find_or_initialize_by(user: current_user, workspace: @workspace, favoritable: @page)
    authorize favorite

    favorite.save! if favorite.new_record?
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Added to favorites."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    favorite = Favorite.find_or_initialize_by(user: current_user, workspace: @workspace, favoritable: @page)
    authorize favorite

    favorite.destroy! if favorite.persisted?
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Removed from favorites."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])
  end
end
