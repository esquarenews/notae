class DatabasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database, only: %i[show update]
  COVER_SHIFT_STEP = 10

  helper_method :cell_value_for, :select_options_for

  def show
    authorize @database
    ensure_default_view!

    @databases = policy_scope(Database).for_workspace(@workspace).order(:created_at)
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @rows = policy_scope(DbRow).for_database(@database).active.ordered.to_a
    @cells = policy_scope(DbCell).for_database(@database).to_a
    @cells_by_key = @cells.index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    @select_options_by_property = build_select_options_by_property
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @view_type = @current_view&.view_type || "table"
    @view_config = @current_view&.config_json.to_h || {}

    resolve_filter_and_sort_settings!
    apply_row_filter!
    sort_rows!
    prepare_board_view_data!
    prepare_calendar_view_data!

    @new_database = Database.new
    @new_property = DbProperty.new
    @new_row = DbRow.new
    @new_database_view = DatabaseView.new
    @database_favorite = policy_scope(Favorite).for_workspace(@workspace).for_user(current_user).find_by(favoritable: @database)
  end

  def create
    @database = @workspace.databases.new(database_params)
    authorize @database

    if @database.save
      @database.database_views.create!(
        workspace: @workspace,
        created_by: current_user,
        name: "Table",
        view_type: :table,
        default: true
      )
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Grid created."
    else
      redirect_to workspace_path(@workspace.slug), alert: @database.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @database, :update?

    @database.assign_attributes(database_update_params)
    apply_header_customizations!

    if @database.changed? || @database.attachment_changes.present?
      @database.save
    end

    if @database.errors.empty?
      redirect_to database_redirect_path, notice: "Grid updated."
    else
      redirect_to database_redirect_path, alert: @database.errors.full_messages.to_sentence
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

  def database_update_params
    params.fetch(:database, ActionController::Parameters.new).permit(:name, :description)
  end

  def database_header_params
    params.fetch(:database, ActionController::Parameters.new)
          .permit(:icon, :icon_action, :cover_action, :cover_shift, :cover_focal_y, :cover_image, :cover_preset_key, :description_action, :description)
  end

  def apply_header_customizations!
    payload = database_header_params
    apply_icon_update!(payload)
    apply_cover_update!(payload)
    apply_description_update!(payload)
  end

  def apply_icon_update!(payload)
    case payload[:icon_action]
    when "set"
      emoji = payload[:icon].to_s.strip
      @database.icon = emoji.presence
    when "clear"
      @database.icon = nil
    end
  end

  def apply_cover_update!(payload)
    case payload[:cover_action]
    when "random"
      @database.cover_preset_key = Database::COVER_PRESET_KEYS.sample
      @database.cover_image.purge if @database.cover_image.attached?
    when "preset"
      requested_key = payload[:cover_preset_key].to_s
      if Database::COVER_PRESET_KEYS.include?(requested_key)
        @database.cover_preset_key = requested_key
        @database.cover_image.purge if @database.cover_image.attached?
      end
    when "upload"
      if payload[:cover_image].present?
        @database.cover_image.attach(payload[:cover_image])
        @database.cover_preset_key = nil
      end
    when "clear"
      @database.cover_preset_key = nil
      @database.cover_image.purge if @database.cover_image.attached?
    end

    shift_delta = { "up" => -COVER_SHIFT_STEP, "down" => COVER_SHIFT_STEP }[payload[:cover_shift].to_s]
    if shift_delta
      base = @database.cover_focal_y || 50
      @database.cover_focal_y = (base + shift_delta).clamp(0, 100)
    elsif payload[:cover_focal_y].present?
      @database.cover_focal_y = payload[:cover_focal_y].to_i.clamp(0, 100)
    end
  end

  def apply_description_update!(payload)
    case payload[:description_action]
    when "set"
      @database.description = payload[:description].to_s.strip.presence
    when "clear"
      @database.description = nil
    end
  end

  def sort_rows!
    return unless @sort_property

    @rows.sort! do |left_row, right_row|
      compare_sort_values(
        sort_value_for_row(left_row, @sort_property),
        sort_value_for_row(right_row, @sort_property)
      ).nonzero? || left_row.title.to_s.downcase <=> right_row.title.to_s.downcase
    end
  end

  def resolve_current_view
    view_id = params[:view_id].presence
    return @database_views.find { |view| view.id.to_s == view_id } if view_id

    @database_views.find(&:default?) || @database_views.first
  end

  def resolve_filter_and_sort_settings!
    sort_property_id = params[:sort_property_id].presence || @view_config["sort_property_id"]
    filter_property_id = params[:filter_property_id].presence || @view_config["filter_property_id"]

    @sort_property = @db_properties.find { |property| property.id.to_s == sort_property_id.to_s }
    configured_direction = params[:sort_direction].presence || @view_config["sort_direction"]
    @sort_direction = configured_direction == "desc" ? "desc" : "asc"

    @filter_property = @db_properties.find { |property| property.id.to_s == filter_property_id.to_s }
    @filter_value = params[:filter_value].presence || @view_config["filter_value"].to_s

    @board_group_property = resolve_property_from_config(:group_property_id, "select")
    @calendar_date_property = resolve_property_from_config(:date_property_id, "date")
    @calendar_month = parse_calendar_month
  end

  def apply_row_filter!
    return if @filter_property.blank? || @filter_value.blank?

    normalized_filter = cast_value_for_property(@filter_property, @filter_value)
    @rows.select! do |row|
      cast_value_for_property(@filter_property, cell_value_for(row, @filter_property)) == normalized_filter
    end
  end

  def prepare_board_view_data!
    return unless @view_type == "board"

    @board_columns = []
    return if @board_group_property.blank?

    values = @rows.map { |row| cell_value_for(row, @board_group_property) }.map(&:strip)
    unique_values = values.reject(&:blank?).uniq.sort

    @board_columns << { value: nil, label: "Unassigned", rows: @rows.select { |row| cell_value_for(row, @board_group_property).blank? } }
    unique_values.each do |value|
      @board_columns << { value: value, label: value, rows: @rows.select { |row| cell_value_for(row, @board_group_property) == value } }
    end
  end

  def prepare_calendar_view_data!
    return unless @view_type == "calendar"

    @calendar_days = (@calendar_month.beginning_of_week(:sunday)..@calendar_month.end_of_month.end_of_week(:sunday)).to_a
    @calendar_rows_by_date = Hash.new { |hash, key| hash[key] = [] }
    return if @calendar_date_property.blank?

    @rows.each do |row|
      parsed_date = parse_date_value(cell_value_for(row, @calendar_date_property))
      next if parsed_date.blank?

      @calendar_rows_by_date[parsed_date] << row
    end
  end

  def resolve_property_from_config(config_key, required_type)
    property_id = params[config_key].presence || @view_config[config_key.to_s]
    @db_properties.find { |property| property.id.to_s == property_id.to_s && property.property_type == required_type }
  end

  def parse_calendar_month
    raw = params[:month].presence || @view_config["month"]
    parsed = raw.present? ? Date.parse(raw.to_s) : Date.current
    parsed.beginning_of_month
  rescue ArgumentError
    Date.current.beginning_of_month
  end

  def parse_date_value(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def cell_value_for(row, property)
    return "" if row.blank? || property.blank?

    @cells_by_key[[ row.id, property.id ]]&.value_text.to_s
  end

  def select_options_for(property)
    return [] if property.blank?

    @select_options_by_property[property.id] || []
  end

  def build_select_options_by_property
    @db_properties.select(&:select?).each_with_object({}) do |property, options|
      values = @rows
               .map { |row| cell_value_for(row, property).to_s.strip }
               .reject(&:blank?)
               .uniq
               .sort
      options[property.id] = values
    end
  end

  def sort_value_for_row(row, property)
    raw_value = cell_value_for(row, property)
    cast_sort_value_for_property(property, raw_value)
  end

  def compare_sort_values(left_value, right_value)
    if left_value.nil? && right_value.nil?
      return 0
    elsif left_value.nil?
      return 1
    elsif right_value.nil?
      return -1
    end

    comparison = left_value <=> right_value
    @sort_direction == "desc" ? -comparison : comparison
  end

  def cast_value_for_property(property, raw_value)
    value = raw_value.to_s.strip
    return nil if value.blank?

    case property.property_type
    when "number"
      Float(value)
    when "date"
      parse_date_value(value)
    when "checkbox"
      parse_boolean_value(value)
    else
      value.downcase
    end
  rescue ArgumentError
    nil
  end

  def cast_sort_value_for_property(property, raw_value)
    if property.checkbox?
      boolean_value = cast_value_for_property(property, raw_value)
      return nil if boolean_value.nil?

      return boolean_value ? 1 : 0
    end

    cast_value_for_property(property, raw_value)
  end

  def parse_boolean_value(value)
    normalized = value.to_s.strip.downcase
    return true if DbCell::TRUTHY_VALUES.include?(normalized)
    return false if DbCell::FALSY_VALUES.include?(normalized)

    nil
  end

  def database_redirect_path
    database_path(
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      sort_property_id: params[:sort_property_id].presence,
      sort_direction: params[:sort_direction].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence
    )
  end

  def ensure_default_view!
    return if @database.database_views.exists?
    return unless policy(DatabaseView.new(database: @database, workspace: @workspace, created_by: current_user)).create?

    @database.database_views.create!(
      workspace: @workspace,
      created_by: current_user,
      name: "Table",
      view_type: :table,
      default: true
    )
  end
end
