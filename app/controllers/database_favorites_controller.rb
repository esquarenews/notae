class DatabaseFavoritesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database

  def create
    favorite = Favorite.find_or_initialize_by(user: current_user, workspace: @workspace, favoritable: @database)
    authorize favorite

    favorite.save! if favorite.new_record?
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Added to favorites."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id),
                alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    favorite = Favorite.find_or_initialize_by(user: current_user, workspace: @workspace, favoritable: @database)
    authorize favorite

    favorite.destroy! if favorite.persisted?
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Removed from favorites."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
  end
end
