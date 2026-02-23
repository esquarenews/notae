class DbCellsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_db_cell

  def update
    authorize @db_cell

    if @db_cell.update(db_cell_params)
      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to cell_redirect_location, notice: "Cell updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render plain: @db_cell.errors.full_messages.to_sentence, status: :unprocessable_entity }
        format.html { redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @db_cell.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])
  end

  def set_db_cell
    @db_cell = policy_scope(DbCell).for_database(@database).find(params[:id])
  end

  def db_cell_params
    params.require(:db_cell).permit(:value_text)
  end

  def cell_redirect_location
    database_path(
      workspace_slug: @workspace.slug,
      id: @database.id,
      sort_property_id: params[:sort_property_id],
      sort_direction: params[:sort_direction],
      anchor: "row_#{@db_cell.db_row_id}"
    )
  end
end
