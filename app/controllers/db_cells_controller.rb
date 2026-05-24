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
      Databases::TimesheetTemplateService.maybe_update_total_for!(@db_cell)
      apply_task_status_row_style!(@db_cell)
      respond_to do |format|
        format.turbo_stream do
          if turbo_inline_cell_update_request?
            render turbo_stream: turbo_stream_update_cell_response(@db_cell)
          else
            render turbo_stream: [
              turbo_stream.update(
                "database_topbar_edited_at",
                partial: "databases/topbar_edited_meta",
                locals: { database: reloaded_database }
              ),
              database_flash_stream("notice", "Cell updated.")
            ]
          end
        end
        format.html { redirect_to cell_redirect_location, notice: "Cell updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: database_flash_stream("alert", @db_cell.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
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
    @db_cell = policy_scope(DbCell).for_database(@database).includes(:db_row, :db_property).find(params[:id])
  end

  def db_cell_params
    permitted = params.require(:db_cell).permit(:value_text)
    if timesheet_clock_cell? && permitted[:value_text].present?
      permitted[:value_text] = normalized_timesheet_clock_value(permitted[:value_text])
    end
    permitted
  end

  def timesheet_clock_cell?
    @db_cell.db_property&.text? &&
      @db_cell.db_property.name.to_s.strip.downcase.in?([ "date/time clock started", "date/time clock stopped" ])
  end

  def normalized_timesheet_clock_value(value)
    parsed_time = Time.zone.parse(value.to_s)
    return value if parsed_time.blank?

    parsed_time.strftime("%Y-%m-%d %H:%M:%S")
  rescue ArgumentError
    value
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
      sort_mode: params[:sort_mode],
      filter_property_id: params[:filter_property_id],
      filter_value: params[:filter_value],
      filter_operator: params[:filter_operator],
      rows_page: params[:rows_page].presence,
      view_settings: params[:view_settings].presence,
      actions_menu: params[:actions_menu].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id,
      task_row_id: params[:task_row_id].presence
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

  def database_flash_stream(type, message)
    turbo_stream.replace(
      "database_flash_messages",
      partial: "shared/flash_messages",
      locals: {
        flash_messages: [ [ type, message ] ],
        flash_dom_id: "database_flash_messages",
        flash_host_class: "notae-db-inline-flash-host"
      }
    )
  end

  def turbo_inline_cell_update_request?
    return false unless request.format.turbo_stream?
    return true if params[:progress_inline_update].to_s == "1"
    return false unless simple_table_render_context?
    return false if params[:split_source].to_s == "row"

    true
  end

  def turbo_stream_update_cell_response(db_cell)
    row = db_cell.db_row
    load_table_row_render_context!(rows: [ row ])

    [
      turbo_stream.update(
        "database_topbar_edited_at",
        partial: "databases/topbar_edited_meta",
        locals: { database: reloaded_database }
      ),
      turbo_stream.replace(
        "row_#{row.id}",
        partial: "databases/table_row",
        locals: table_row_locals(row: row)
      ),
      database_flash_stream("notice", "Cell updated.")
    ]
  end

  def current_database_view_for_response
    @current_database_view_for_response ||= begin
      views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
      requested_id = params[:view_id].to_s.presence
      if requested_id.present?
        views.find { |view| view.id.to_s == requested_id }
      else
        views.find(&:default?) || views.first
      end
    end
  end

  def simple_table_render_context?
    current_view = current_database_view_for_response
    view_config = current_view&.config_json.to_h || {}

    return false unless (current_view&.view_type || "table") == "table"
    return false if params[:sort_property_id].present? || params[:filter_property_id].present?
    return false if view_config["sort_property_id"].present? || view_config["filter_property_id"].present?

    true
  end

  def load_table_row_render_context!(rows:)
    @current_view = current_database_view_for_response
    @db_properties = db_properties_for_database
    @view_config = @current_view&.config_json.to_h || {}
    visible_property_ids = Array(@view_config["visible_property_ids"]).map(&:to_s)
    @visible_db_properties = if visible_property_ids.any?
      @db_properties.select { |property| visible_property_ids.include?(property.id.to_s) }
    else
      @db_properties
    end
    conditional_property_id = @view_config["conditional_color_property_id"].to_s
    @conditional_color_mode = @view_config["conditional_color_mode"].to_s == "overdue" ? "overdue" : "none"
    @conditional_color_property = @db_properties.find do |property|
      property.id.to_s == conditional_property_id && property.date?
    end
    property_ids = @visible_db_properties.map(&:id)
    @cells_by_key = if rows.empty? || property_ids.empty?
      {}
    else
      DbCell
        .where(workspace_id: @workspace.id)
        .where(db_row_id: rows.map(&:id), db_property_id: property_ids)
        .to_a
        .index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    end
    @select_options_by_property = build_select_options_by_property_for_rows(properties: @visible_db_properties)
  end

  def build_select_options_by_property_for_rows(properties:)
    build_select_options_lookup(database: @database, properties: properties)
  end

  def table_row_locals(row:, autofocus_title: false, highlight_row_id: params[:highlight_row_id].presence)
    can_update_rows = policy(@database).update? && !@database.locked?

    {
      row: row,
      workspace: @workspace,
      database: @database,
      current_view: @current_view,
      row_params: table_row_params,
      visible_properties: @visible_db_properties,
      cells_by_key: @cells_by_key,
      can_create_rows: can_update_rows,
      can_update_rows: can_update_rows,
      can_update_cells: can_update_rows,
      can_destroy_rows: policy(@database).destroy? && !@database.locked?,
      row_color_options: row_color_options,
      page_search_url: workspace_document_targets_path(workspace_slug: @workspace.slug, kind: "page"),
      name_column_style_classes: name_column_style_classes_for(@database),
      autofocus_title: autofocus_title,
      highlight_row_id: highlight_row_id
    }
  end

  def table_row_params
    {
      view_id: @current_view&.id,
      month: params[:month].presence,
      sort_property_id: params[:sort_property_id].presence,
      sort_direction: params[:sort_direction].presence,
      sort_mode: params[:sort_mode].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      rows_page: params[:rows_page].presence,
      highlight_row_id: params[:highlight_row_id].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence,
      task_row_id: params[:task_row_id].presence
    }.compact
  end

  def db_properties_for_database
    @db_properties_for_database ||= policy_scope(DbProperty).for_database(@database).ordered.to_a
  end

  def row_color_options
    [
      [ "Default", "default" ],
      [ "Gray", "gray" ],
      [ "Brown", "brown" ],
      [ "Orange", "orange" ],
      [ "Yellow", "yellow" ],
      [ "Green", "green" ],
      [ "Blue", "blue" ],
      [ "Purple", "purple" ],
      [ "Pink", "pink" ],
      [ "Red", "red" ]
    ]
  end

  def apply_task_status_row_style!(db_cell)
    property = db_cell.db_property
    return unless property.select?
    return unless property.name.to_s.strip.casecmp("status").zero?

    row = db_cell.db_row.reload
    status_value = normalize_task_status_value(db_cell.value_text)
    if status_value == "done"
      row.apply_row_style_action!(action: "set_color", text_color: "gray")
    elsif row.row_text_color == "gray"
      row.apply_row_style_action!(action: "set_color", text_color: "default")
    end

    row.save! if row.changed?
  end

  def reloaded_database
    @reloaded_database ||= @database.reload
  end
end
