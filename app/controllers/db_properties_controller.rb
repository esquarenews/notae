class DbPropertiesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :ensure_database_unlocked!
  before_action :set_db_property, only: %i[update destroy]

  def create
    @db_property = @database.db_properties.new(db_property_params)
    authorize @db_property

    if @db_property.save
      seed_cells_for_existing_rows(@db_property)
      append_property_to_active_view_visibility(@db_property)
      redirect_to database_redirect_location, notice: "Column added."
    else
      redirect_to database_redirect_location, alert: @db_property.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @db_property
    @db_property.destroy!
    redirect_to database_redirect_location, notice: "Column removed."
  end

  def update
    authorize @db_property

    @db_property.assign_attributes(db_property_update_params)
    apply_db_property_style_update!
    apply_db_property_select_option_update!

    if @db_property.save
      redirect_to database_redirect_location, notice: db_property_update_notice
    else
      redirect_to database_redirect_location, alert: @db_property.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
  end

  def set_db_property
    @db_property = policy_scope(DbProperty).for_database(@database).find(params[:id])
  end

  def db_property_params
    params.require(:db_property).permit(:name, :property_type, select_options_json: [])
  end

  def db_property_update_params
    params.fetch(:db_property, ActionController::Parameters.new).permit(:name)
  end

  def db_property_style_params
    params.fetch(:db_property, ActionController::Parameters.new).permit(:style_action, :text_color, :background_color)
  end

  def db_property_select_option_params
    params.fetch(:db_property, ActionController::Parameters.new).permit(:select_option_action, :select_option_value)
  end

  def apply_db_property_style_update!
    payload = db_property_style_params
    return if payload[:style_action].blank?

    @db_property.apply_column_style_action!(
      action: payload[:style_action],
      text_color: payload[:text_color],
      background_color: payload[:background_color]
    )
  end

  def apply_db_property_select_option_update!
    payload = db_property_select_option_params
    return if payload[:select_option_action].blank?

    @db_property.apply_select_option_action!(
      action: payload[:select_option_action],
      option_value: payload[:select_option_value]
    )
  end

  def db_property_update_notice
    return "Column updated." if db_property_style_params[:style_action].present?
    return "Dropdown updated." if db_property_select_option_params[:select_option_action].present?

    "Column renamed."
  end

  def seed_cells_for_existing_rows(db_property)
    row_ids = policy_scope(DbRow).for_database(@database).active.pluck(:id)
    return if row_ids.empty?

    existing_row_ids = DbCell.where(db_property_id: db_property.id, db_row_id: row_ids).pluck(:db_row_id)
    existing_lookup = existing_row_ids.each_with_object({}) { |row_id, memo| memo[row_id] = true }

    now = Time.current
    missing_cells = row_ids.each_with_object([]) do |row_id, memo|
      next if existing_lookup[row_id]

      memo << {
        id: SecureRandom.uuid,
        workspace_id: @workspace.id,
        db_row_id: row_id,
        db_property_id: db_property.id,
        value_text: default_cell_value_for_property(db_property),
        created_at: now,
        updated_at: now
      }
    end
    return if missing_cells.empty?

    DbCell.insert_all(missing_cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
  end

  def default_cell_value_for_property(db_property)
    return DbCell::PROGRESS_MIN.to_s if db_property.progress?

    ""
  end

  def append_property_to_active_view_visibility(db_property)
    view_id = params[:view_id].presence
    return if view_id.blank?

    database_view = policy_scope(DatabaseView).for_database(@database).find_by(id: view_id)
    return if database_view.blank?
    return unless policy(database_view).update?

    config = database_view.config_json.to_h.deep_dup
    visible_ids = Array(config["visible_property_ids"]).map(&:to_s).reject(&:blank?).uniq
    return if visible_ids.empty?
    return if visible_ids.include?(db_property.id.to_s)

    visible_ids << db_property.id.to_s
    config["visible_property_ids"] = visible_ids
    database_view.update_columns(config_json: config, updated_at: Time.current)
  end

  def database_redirect_location
    database_path(
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      sort_property_id: params[:sort_property_id].presence,
      sort_direction: params[:sort_direction].presence,
      sort_mode: params[:sort_mode].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      rows_page: params[:rows_page].presence,
      view_settings: params[:view_settings].presence,
      view_settings_section: params[:view_settings_section].presence,
      actions_menu: params[:actions_menu].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence,
      task_row_id: params[:task_row_id].presence
    )
  end

  def ensure_database_unlocked!
    return unless @database.locked?

    redirect_to database_redirect_location, alert: "Grid is locked. Unlock to make changes."
  end
end
