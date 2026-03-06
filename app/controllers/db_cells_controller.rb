class DbCellsController < ApplicationController
  include DatabaseTablePresentation
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :ensure_database_unlocked!
  before_action :set_db_cell
  track_request_performance_for :update

  def update
    authorize @db_cell

    if @db_cell.update(db_cell_params)
      apply_task_status_row_style!(@db_cell)
      @database.reload
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "database_topbar_edited_at",
            partial: "databases/topbar_edited_meta",
            locals: { database: @database }
          )
        end
        format.html { redirect_to cell_redirect_location, notice: "Cell updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render plain: @db_cell.errors.full_messages.to_sentence, status: :unprocessable_entity }
        format.html { redirect_to cell_redirect_location, alert: @db_cell.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
  end

  def set_db_cell
    @db_cell = policy_scope(DbCell).for_database(@database).find(params[:id])
  end

  def db_cell_params
    params.require(:db_cell).permit(:value_text)
  end

  def cell_redirect_location
    split_page_id, split_source, split_row_id = split_params_for_cell_context

    path_params = {
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      sort_property_id: params[:sort_property_id],
      sort_direction: params[:sort_direction],
      filter_property_id: params[:filter_property_id],
      filter_value: params[:filter_value],
      filter_operator: params[:filter_operator],
      view_settings: params[:view_settings].presence,
      actions_menu: params[:actions_menu].presence,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id
    }.compact
    path_params[:anchor] = "row_#{@db_cell.db_row_id}" if @db_cell.present?
    database_path(path_params)
  end

  def split_params_for_cell_context
    split_page_id = params[:split_page_id].presence
    split_source = params[:split_source].presence
    split_row_id = params[:split_row_id].presence

    if split_source == "row" && split_row_id.present? && split_row_id != @db_cell.db_row_id.to_s
      [ nil, nil, nil ]
    else
      [ split_page_id, split_source, split_row_id ]
    end
  end

  def ensure_database_unlocked!
    return unless @database.locked?

    redirect_to cell_redirect_location, alert: "Grid is locked. Unlock to make changes."
  end

  def apply_task_status_row_style!(db_cell)
    property = db_cell.db_property
    return unless property.select?
    return unless property.name.to_s.strip.casecmp("status").zero?

    row = db_cell.db_row
    status_value = normalize_task_status_value(db_cell.value_text)
    if status_value == "done"
      row.apply_row_style_action!(action: "set_color", text_color: "gray")
    elsif row.row_text_color == "gray"
      row.apply_row_style_action!(action: "set_color", text_color: "default")
    end

    row.save! if row.changed?
  end

end
