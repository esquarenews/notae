class DbRowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_db_row, only: :move

  def create
    @db_row = @database.db_rows.new(db_row_params)
    @db_row.title = "Untitled row" if @db_row.title.blank?
    authorize @db_row

    if @db_row.save
      seed_cells_for_row(@db_row)
      assign_date_value_to_row(@db_row)
      redirect_to database_path(
        workspace_slug: @workspace.slug,
        id: @database.id,
        view_id: params[:view_id],
        month: params[:month]
      ), notice: "Row created."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @db_row.errors.full_messages.to_sentence
    end
  end

  def move
    authorize @db_row, :update?
    property =
      if params[:property_id].present?
        policy_scope(DbProperty).for_database(@database).find(params[:property_id])
      end

    DbRows::MoveService.call(
      row: @db_row,
      database: @database,
      workspace: @workspace,
      property: property,
      target_value: params[:target_value],
      target_index: params[:target_index]
    )

    respond_to do |format|
      format.json { head :ok }
      format.html do
        redirect_to database_path(
          workspace_slug: @workspace.slug,
          id: @database.id,
          view_id: params[:view_id],
          month: params[:month]
        ), notice: "Row moved."
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

  def db_row_params
    params.require(:db_row).permit(:title)
  end

  def set_db_row
    @db_row = policy_scope(DbRow).for_database(@database).find(params[:id])
  end

  def seed_cells_for_row(row)
    policy_scope(DbProperty).for_database(@database).ordered.each do |db_property|
      row.db_cells.find_or_create_by!(db_property:, workspace: @workspace) do |cell|
        cell.value_text = ""
      end
    end
  end

  def assign_date_value_to_row(row)
    date_property_id = params[:date_property_id].presence
    date_value = params[:date_value].presence
    return if date_property_id.blank? || date_value.blank?

    date_property = policy_scope(DbProperty).for_database(@database).find_by(id: date_property_id, property_type: :date)
    return if date_property.blank?

    row.db_cells.find_or_create_by!(db_property: date_property, workspace: @workspace) do |cell|
      cell.value_text = date_value
    end.tap do |cell|
      cell.update!(value_text: date_value)
    end
  end
end
