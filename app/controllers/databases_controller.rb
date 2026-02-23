class DatabasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database, only: :show

  def show
    authorize @database

    @databases = policy_scope(Database).for_workspace(@workspace).order(:created_at)
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @rows = policy_scope(DbRow).for_database(@database).active.order(:created_at).to_a
    @cells = policy_scope(DbCell).for_database(@database).to_a
    @cells_by_key = @cells.index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }

    @sort_property = @db_properties.find { |property| property.id == params[:sort_property_id] }
    @sort_direction = params[:sort_direction] == "desc" ? "desc" : "asc"
    sort_rows!

    @new_database = Database.new
    @new_property = DbProperty.new
    @new_row = DbRow.new
  end

  def create
    @database = @workspace.databases.new(database_params)
    authorize @database

    if @database.save
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Database created."
    else
      redirect_to workspace_path(@workspace.slug), alert: @database.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:id])
  end

  def database_params
    params.require(:database).permit(:name)
  end

  def sort_rows!
    return unless @sort_property

    @rows.sort_by! do |row|
      cell_value = @cells_by_key[[ row.id, @sort_property.id ]]&.value_text.to_s.downcase
      [ cell_value, row.title.to_s.downcase ]
    end
    @rows.reverse! if @sort_direction == "desc"
  end
end
