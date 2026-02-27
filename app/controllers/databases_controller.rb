class DatabasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database, only: %i[show update duplicate archive export_csv]
  before_action :set_archived_database, only: %i[restore destroy]
  COVER_SHIFT_STEP = 10
  FILTER_OPERATORS = %w[eq before after].freeze

  helper_method :cell_value_for, :select_options_for, :conditional_color_class_for_row

  def show
    authorize @database
    ensure_default_view!

    @databases = policy_scope(Database).for_workspace(@workspace).active.order(:created_at)
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @rows = policy_scope(DbRow).for_database(@database).active.ordered.to_a
    @cells = policy_scope(DbCell).for_database(@database).to_a
    @cells_by_key = @cells.index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    @select_options_by_property = build_select_options_by_property
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @view_type = @current_view&.view_type || "table"
    @view_config = @current_view&.config_json.to_h || {}
    @linkable_pages = policy_scope(Page).for_workspace(@workspace).active.order(updated_at: :desc).to_a
    @linkable_pages_by_id = @linkable_pages.index_by(&:id)
    @split_page = resolve_split_page

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
    @can_archive_database = policy(@database).archive?
    @recent_database_audit_events = policy_scope(AuditEvent)
                                      .where(workspace_id: @workspace.id, auditable: @database)
                                      .recent_first
                                      .limit(10)
                                      .to_a
    @database_versions = @database.versions.reorder(created_at: :desc).limit(10).to_a
    @database_plain_text = build_database_plain_text
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
      log_database_audit_event!(action: "create", kind: "database_created")
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Grid created."
    else
      redirect_to workspace_path(@workspace.slug), alert: @database.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @database, :update?

    if @database.locked? && !unlocking_database_request?
      @database.errors.add(:base, "Grid is locked. Unlock to make changes.")
    else
      @database.assign_attributes(database_update_params)
      apply_header_customizations!
      apply_linked_page_update!
    end

    database_changed = @database.changed? || @database.attachment_changes.present?
    if database_changed
      @database.save
    end

    if @database.errors.empty?
      log_database_audit_event!(action: "update", kind: "database_updated", changed_fields: @database.saved_changes.keys) if database_changed
      respond_to do |format|
        format.html { redirect_to database_redirect_path, notice: "Grid updated." }
        format.json do
          render json: {
            id: @database.id,
            name: @database.name,
            icon: @database.icon,
            updated_at: @database.updated_at&.iso8601(6)
          }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.html { redirect_to database_redirect_path, alert: @database.errors.full_messages.to_sentence }
        format.json { render json: { errors: @database.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def duplicate
    authorize @database, :show?
    authorize Database.new(workspace: @workspace, name: "#{@database.name} (copy)"), :create?

    duplicated_database = Databases::DuplicateService.call(
      database: @database,
      created_by: current_user,
      name: params.dig(:database, :name)
    )
    log_database_audit_event!(action: "duplicate", kind: "database_duplicated", source_database_id: @database.id, auditable: duplicated_database)
    redirect_to database_path(workspace_slug: @workspace.slug, id: duplicated_database.id), notice: "Grid duplicated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_path, alert: error.record.errors.full_messages.to_sentence
  end

  def archive
    authorize @database, :archive?
    @database.archive!
    log_database_audit_event!(action: "delete", kind: "database_archived")
    redirect_to workspace_trash_path(workspace_slug: @workspace.slug), notice: "Grid archived."
  end

  def restore
    authorize @database, :restore?
    @database.restore!
    log_database_audit_event!(action: "restore", kind: "database_restored")
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Grid restored."
  end

  def destroy
    authorize @database, :destroy?

    unless @database.archived?
      redirect_to workspace_trash_path(workspace_slug: @workspace.slug), alert: "Archive the grid before deleting it permanently."
      return
    end

    @database.destroy!
    redirect_to workspace_trash_path(workspace_slug: @workspace.slug), notice: "Grid deleted permanently."
  end

  def export_csv
    authorize @database, :show?

    send_data Databases::CsvExportService.call(database: @database),
              filename: "#{@database.name.parameterize.presence || "grid"}-#{Time.zone.today}.csv",
              type: "text/csv; charset=utf-8"
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:id])
  end

  def set_archived_database
    @database = policy_scope(Database).for_workspace(@workspace).archived.find(params[:id])
  end

  def database_params
    params.require(:database).permit(:name)
  end

  def database_update_params
    permitted = params.fetch(:database, ActionController::Parameters.new).permit(:name, :description, :locked, :small_text, :font_style)
    permitted.delete(:locked) unless policy(@database).permissions?
    permitted
  end

  def database_link_params
    params.fetch(:database, ActionController::Parameters.new).permit(:linked_page_id, :linked_page_action)
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

  def apply_linked_page_update!
    payload = database_link_params
    action = payload[:linked_page_action].to_s

    if action == "clear"
      @database.linked_page = nil
      @clear_split_page = true
      return
    end

    if action == "create_page"
      linked_page = create_linked_page_for_database
      @database.linked_page = linked_page if linked_page.present?
      @redirect_split_page_id = linked_page&.id
      @redirect_split_source = "database"
      return
    end

    return unless payload.key?(:linked_page_id)

    resolved_page = resolve_linkable_page(payload[:linked_page_id])
    return if resolved_page == :invalid

    @database.linked_page = resolved_page
    @clear_split_page = true if resolved_page.nil?
    @redirect_split_page_id = resolved_page&.id
    @redirect_split_source = "database" if resolved_page.present?
  end

  def create_linked_page_for_database
    page_title = [ @database.name.presence || "Untitled grid", "notes" ].join(" ")
    page = @workspace.pages.new(title: page_title, created_by: current_user)
    unless policy(page).create?
      @database.errors.add(:base, "You are not authorized to create Notarum in this workspace.")
      return nil
    end

    return page if page.save

    @database.errors.add(:base, page.errors.full_messages.to_sentence)
    nil
  end

  def resolve_linkable_page(raw_id)
    candidate_id = raw_id.to_s.strip
    return nil if candidate_id.blank?

    linked_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: candidate_id)
    return linked_page if linked_page.present?

    @database.errors.add(:linked_page_id, "must reference an accessible page in this workspace")
    :invalid
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
    conditional_color_property_id = params[:conditional_color_property_id].presence || @view_config["conditional_color_property_id"]

    @sort_property = @db_properties.find { |property| property.id.to_s == sort_property_id.to_s }
    configured_direction = params[:sort_direction].presence || @view_config["sort_direction"]
    @sort_direction = configured_direction == "desc" ? "desc" : "asc"

    @filter_property = @db_properties.find { |property| property.id.to_s == filter_property_id.to_s }
    @filter_value = params[:filter_value].presence || @view_config["filter_value"].to_s
    @filter_operator = normalize_filter_operator(params[:filter_operator].presence || @view_config["filter_operator"])

    @visible_property_ids = resolve_visible_property_ids
    @visible_db_properties = if @visible_property_ids.present?
      @db_properties.select { |property| @visible_property_ids.include?(property.id.to_s) }
    else
      @db_properties
    end

    @conditional_color_mode = normalize_conditional_color_mode(
      params[:conditional_color_mode].presence || @view_config["conditional_color_mode"]
    )
    @conditional_color_property = @db_properties.find do |property|
      property.id.to_s == conditional_color_property_id.to_s && property.date?
    end

    @board_group_property = resolve_property_from_config(:group_property_id, "select")
    @calendar_date_property = resolve_property_from_config(:date_property_id, "date")
    @calendar_month = parse_calendar_month
  end

  def apply_row_filter!
    return if @filter_property.blank? || @filter_value.blank?

    normalized_filter = cast_value_for_property(@filter_property, @filter_value)
    return if normalized_filter.nil?

    @rows.select! do |row|
      row_value = cast_value_for_property(@filter_property, cell_value_for(row, @filter_property))
      filter_match?(row_value, normalized_filter)
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

  def filter_match?(row_value, normalized_filter)
    return false if row_value.nil?

    case @filter_operator
    when "before"
      return false unless @filter_property.number? || @filter_property.date?

      row_value < normalized_filter
    when "after"
      return false unless @filter_property.number? || @filter_property.date?

      row_value > normalized_filter
    else
      row_value == normalized_filter
    end
  end

  def normalize_filter_operator(value)
    candidate = value.to_s
    FILTER_OPERATORS.include?(candidate) ? candidate : "eq"
  end

  def resolve_visible_property_ids
    requested_ids = params[:visible_property_ids]
    configured_ids = @view_config["visible_property_ids"]
    candidate_ids = requested_ids.present? ? requested_ids : configured_ids

    Array(candidate_ids)
      .map(&:to_s)
      .select { |property_id| @db_properties.any? { |property| property.id.to_s == property_id } }
      .uniq
  end

  def normalize_conditional_color_mode(value)
    value.to_s == "overdue" ? "overdue" : "none"
  end

  def conditional_color_class_for_row(row)
    return nil unless @conditional_color_mode == "overdue"
    return nil if @conditional_color_property.blank?

    due_date = cast_value_for_property(@conditional_color_property, cell_value_for(row, @conditional_color_property))
    return nil unless due_date.is_a?(Date)
    return nil unless due_date < Date.current

    "is-overdue-highlight"
  end

  def unlocking_database_request?
    return false unless params.key?(:database)
    return false unless params[:database].respond_to?(:key?) && params[:database].key?(:locked)

    ActiveModel::Type::Boolean.new.cast(params.dig(:database, :locked)) == false
  end

  def database_redirect_path
    split_page_id = @clear_split_page ? nil : (@redirect_split_page_id || params[:split_page_id].presence)
    split_source = @clear_split_page ? nil : (@redirect_split_source || params[:split_source].presence)
    split_row_id = @clear_split_page ? nil : params[:split_row_id].presence

    database_path(
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      sort_property_id: params[:sort_property_id].presence,
      sort_direction: params[:sort_direction].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      view_settings: params[:view_settings].presence,
      actions_menu: params[:actions_menu].presence,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id
    )
  end

  def resolve_split_page
    split_page_id = params[:split_page_id].presence
    return nil if split_page_id.blank?

    policy_scope(Page).for_workspace(@workspace).active.find_by(id: split_page_id)
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

  def build_database_plain_text
    headers = [ "Name" ] + @visible_db_properties.map(&:name)
    rows = @rows.map do |row|
      [ row.title ] + @visible_db_properties.map { |property| cell_value_for(row, property) }
    end

    [ headers, *rows ].map { |line| line.join("\t") }.join("\n")
  end

  def log_database_audit_event!(action:, kind:, auditable: @database, **metadata)
    AuditEventLogger.log!(
      workspace: @workspace,
      actor: current_user,
      action: action,
      metadata: metadata.merge(kind: kind, database_id: @database.id).compact,
      auditable: auditable
    )
  end
end
