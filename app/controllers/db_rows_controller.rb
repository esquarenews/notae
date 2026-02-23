class DbRowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database

  def create
    @db_row = @database.db_rows.new(db_row_params)
    @db_row.title = "Untitled row" if @db_row.title.blank?
    authorize @db_row

    if @db_row.save
      seed_cells_for_row(@db_row)
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Row created."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @db_row.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])
  end

  def db_row_params
    params.require(:db_row).permit(:title)
  end

  def seed_cells_for_row(row)
    policy_scope(DbProperty).for_database(@database).ordered.each do |db_property|
      row.db_cells.find_or_create_by!(db_property:, workspace: @workspace) do |cell|
        cell.value_text = ""
      end
    end
  end
end
