class DatabaseViewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_database_view, only: %i[update set_default]

  def create
    @database_view = @database.database_views.new(database_view_params)
    @database_view.created_by = current_user
    authorize @database_view

    if @database_view.save
      @database_view.set_as_default! if @database_view.default?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: @database_view.id), notice: "View saved."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @database_view.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @database_view

    if @database_view.update(database_view_params)
      @database_view.set_as_default! if @database_view.default?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: @database_view.id), notice: "View updated."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: @database_view.id), alert: @database_view.errors.full_messages.to_sentence
    end
  end

  def set_default
    authorize @database_view, :set_default?
    @database_view.set_as_default!
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: @database_view.id), notice: "Default view set."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])
  end

  def set_database_view
    @database_view = policy_scope(DatabaseView).for_database(@database).find(params[:id])
  end

  def database_view_params
    permitted = params.require(:database_view).permit(
      :name,
      :view_type,
      :default,
      :sort_property_id,
      :sort_direction,
      :filter_property_id,
      :filter_value,
      :group_property_id,
      :date_property_id
    )

    config = {
      "sort_property_id" => permitted.delete(:sort_property_id).presence,
      "sort_direction" => normalize_sort_direction(permitted.delete(:sort_direction)),
      "filter_property_id" => permitted.delete(:filter_property_id).presence,
      "filter_value" => permitted.delete(:filter_value).presence,
      "group_property_id" => permitted.delete(:group_property_id).presence,
      "date_property_id" => permitted.delete(:date_property_id).presence
    }.compact

    permitted[:config_json] = config
    permitted
  end

  def normalize_sort_direction(value)
    direction = value.to_s
    return direction if %w[asc desc].include?(direction)

    nil
  end
end
