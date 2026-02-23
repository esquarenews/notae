class DbPropertiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_db_property, only: :destroy

  def create
    @db_property = @database.db_properties.new(db_property_params)
    authorize @db_property

    if @db_property.save
      seed_cells_for_existing_rows(@db_property)
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Column added."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @db_property.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @db_property
    @db_property.destroy!
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Column removed."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])
  end

  def set_db_property
    @db_property = policy_scope(DbProperty).for_database(@database).find(params[:id])
  end

  def db_property_params
    params.require(:db_property).permit(:name, :property_type)
  end

  def seed_cells_for_existing_rows(db_property)
    policy_scope(DbRow).for_database(@database).active.find_each do |row|
      row.db_cells.find_or_create_by!(db_property:, workspace: @workspace) do |cell|
        cell.value_text = ""
      end
    end
  end
end
