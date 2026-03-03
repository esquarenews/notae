class DatabasesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database, only: %i[show update duplicate archive export_csv permissions kanbanize]
  before_action :set_archived_database, only: %i[restore destroy]
  COVER_SHIFT_STEP = 10
  FILTER_OPERATORS = %w[eq before after].freeze
  TASK_STATUS_OPTIONS = [ "not started", "planning", "started", "on hold", "complete" ].freeze
  TASK_STATUS_CLASS_MAP = {
    "not started" => "is-status-not-started",
    "planning" => "is-status-planning",
    "started" => "is-status-started",
    "on hold" => "is-status-on-hold",
    "complete" => "is-status-complete"
  }.freeze

  helper_method :cell_value_for, :select_options_for, :conditional_color_class_for_row, :select_input_classes_for

  def show
    authorize @database
    ensure_default_view!

    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @databases = policy_scope(Database).for_workspace(@workspace).active.order(:created_at)
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @rows = policy_scope(DbRow).for_database(@database).active.ordered.to_a
    @archived_rows = policy_scope(DbRow).for_database(@database).where.not(archived_at: nil).ordered.to_a
    ensure_cells_for_rendered_rows!
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
    @database_share_links =
      if policy(@database).permissions?
        policy_scope(DatabaseShareLink).for_database(@database).recent_first.to_a
      else
        []
      end
    @shared_user_ids = @database.database_shares.pluck(:user_id)
    database_comment_probe = Comment.new(commentable: @database, workspace: @workspace, author: current_user, body: "draft")
    @can_comment_on_database = policy(database_comment_probe).create?
    @new_database_comment = Comment.new
    @database_comments = policy_scope(Comment)
                           .for_workspace(@workspace)
                           .where(commentable: @database)
                           .includes(:author, :resolved_by)
                           .order(created_at: :desc)
                           .to_a
  end

  def create
    @database = @workspace.databases.new(database_params)
    @database.created_by = current_user
    template = normalize_template(params[:template])
    apply_template_default_name!(template)
    apply_quick_create_name!
    authorize @database

    ActiveRecord::Base.transaction do
      @database.save!
      table_view = ensure_default_view!
      apply_template!(template, table_view:)
      log_database_audit_event!(action: "create", kind: "database_created")
    end

    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Grid created."
  rescue ActiveRecord::RecordInvalid => error
    message = @database.errors.full_messages.to_sentence.presence || error.record.errors.full_messages.to_sentence
    redirect_to workspace_path(@workspace.slug), alert: message
  end

  def kanbanize
    authorize @database, :update?

    if @database.locked?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: "Grid is locked. Unlock to make changes."
      return
    end

    board_view = nil
    ActiveRecord::Base.transaction do
      status_property = resolve_or_create_kanban_group_property!
      board_view = resolve_or_create_kanban_view!
      config = board_view.config_json.to_h
      config["group_property_id"] = status_property.id
      board_view.update!(config_json: config)
    end

    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: board_view.id), notice: "Switched to Kanban view."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: error.record.errors.full_messages.to_sentence
  end

  def permissions
    authorize @database, :permissions?

    permission_mode = params.require(:database).permit(:permission_mode)[:permission_mode]
    shared_user_ids = Array(params.dig(:database, :shared_user_ids)).reject(&:blank?)
    allowed_user_ids =
      if permission_mode == "specific_users"
        @workspace.memberships.where(user_id: shared_user_ids).pluck(:user_id)
      else
        []
      end

    ActiveRecord::Base.transaction do
      @database.update!(permission_mode: permission_mode)

      @database.database_shares.where.not(user_id: allowed_user_ids).delete_all
      allowed_user_ids.each do |user_id|
        @database.database_shares.find_or_create_by!(user_id: user_id) do |share|
          share.created_by = current_user
        end
      end

      log_database_audit_event!(
        action: "share",
        kind: "database_permissions_updated",
        permission_mode: @database.permission_mode,
        shared_user_ids: allowed_user_ids
      )
    end

    redirect_to database_redirect_path, notice: "Grid permissions updated."
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_path, alert: error.message
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

  def apply_quick_create_name!
    return unless params[:quick_create].to_s == "1"

    base_name = @database.name.to_s.strip.presence || "Untitled grid"
    @database.name = next_available_database_name(base_name)
  end

  def next_available_database_name(base_name)
    return base_name unless @workspace.databases.exists?(name: base_name)

    suffix = 2
    loop do
      candidate_name = "#{base_name} #{suffix}"
      return candidate_name unless @workspace.databases.exists?(name: candidate_name)

      suffix += 1
    end
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

  def select_input_classes_for(property, value)
    classes = [ "notae-db-cell-input" ]
    return classes.join(" ") unless task_status_property?(property)

    normalized_value = normalize_task_status_value(value)
    classes << "notae-db-cell-select-status"
    classes << TASK_STATUS_CLASS_MAP[normalized_value] if TASK_STATUS_CLASS_MAP.key?(normalized_value)
    classes.join(" ")
  end

  def build_select_options_by_property
    @db_properties.select(&:select?).each_with_object({}) do |property, options|
      seen = {}
      values = []

      if task_status_property?(property)
        TASK_STATUS_OPTIONS.each do |status|
          seen[status] = true
          values << status
        end
      end

      @rows.each do |row|
        value = cell_value_for(row, property).to_s.strip
        next if value.blank?

        normalized = task_status_property?(property) ? normalize_task_status_value(value) : value
        next if normalized.blank?
        next if seen.key?(normalized)

        seen[normalized] = true
        values << normalized
      end

      options[property.id] = task_status_property?(property) ? values : values.sort
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
      view_settings_section: params[:view_settings_section].presence,
      actions_menu: params[:actions_menu].presence,
      options_menu: params[:options_menu].presence,
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

  def ensure_cells_for_rendered_rows!
    return if @rows.empty? || @db_properties.empty?

    row_ids = @rows.map(&:id)
    property_ids = @db_properties.map(&:id)

    existing_keys = policy_scope(DbCell)
                    .for_database(@database)
                    .where(db_row_id: row_ids, db_property_id: property_ids)
                    .pluck(:db_row_id, :db_property_id)
                    .to_set

    now = Time.current
    missing_cells = []

    row_ids.each do |row_id|
      property_ids.each do |property_id|
        next if existing_keys.include?([ row_id, property_id ])

        missing_cells << {
          id: SecureRandom.uuid,
          workspace_id: @workspace.id,
          db_row_id: row_id,
          db_property_id: property_id,
          value_text: "",
          created_at: now,
          updated_at: now
        }
      end
    end

    return if missing_cells.empty?

    DbCell.insert_all(missing_cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
  end

  def normalize_template(raw_template)
    template = raw_template.to_s
    return "tasks" if template == "tasks"

    "blank"
  end

  def apply_template_default_name!(template)
    return unless @database.name.to_s.strip.blank?

    @database.name = template == "tasks" ? "Tasks grid" : "Untitled grid"
  end

  def apply_template!(template, table_view:)
    return unless template == "tasks"

    build_tasks_template!(table_view:)
  end

  def build_tasks_template!(table_view:)
    created_properties = []
    created_properties << @database.db_properties.create!(
      workspace: @workspace,
      name: "Status",
      property_type: :select
    )
    created_properties << @database.db_properties.create!(
      workspace: @workspace,
      name: "Date created",
      property_type: :date
    )
    created_properties << @database.db_properties.create!(
      workspace: @workspace,
      name: "Due date",
      property_type: :date
    )
    created_properties << @database.db_properties.create!(
      workspace: @workspace,
      name: "Notes",
      property_type: :text
    )

    return if table_view.blank?

    config = table_view.config_json.to_h
    config["visible_property_ids"] = created_properties.map { |property| property.id.to_s }
    table_view.update!(config_json: config)
  end

  def task_status_property?(property)
    property.present? && property.select? && property.name.to_s.strip.casecmp("status").zero?
  end

  def normalize_task_status_value(value)
    value.to_s.strip.downcase
  end

  def resolve_or_create_kanban_group_property!
    status_property = @database.db_properties.ordered.find { |property| task_status_property?(property) }
    return status_property if status_property.present?

    selectable_property = @database.db_properties.ordered.find(&:select?)
    return selectable_property if selectable_property.present?

    @database.db_properties.create!(
      workspace: @workspace,
      name: next_available_property_name("Status"),
      property_type: :select
    )
  end

  def resolve_or_create_kanban_view!
    existing_board = @database.database_views.ordered.find { |view| view.view_type == "board" }
    return existing_board if existing_board.present?

    @database.database_views.create!(
      workspace: @workspace,
      created_by: current_user,
      name: next_available_view_name("Kanban"),
      view_type: :board,
      default: false
    )
  end

  def next_available_property_name(base_name)
    existing_names = @database.db_properties.pluck(:name).map { |name| name.to_s.downcase }
    return base_name unless existing_names.include?(base_name.downcase)

    suffix = 2
    loop do
      candidate = "#{base_name} #{suffix}"
      return candidate unless existing_names.include?(candidate.downcase)

      suffix += 1
    end
  end

  def next_available_view_name(base_name)
    existing_names = @database.database_views.pluck(:name).map { |name| name.to_s.downcase }
    return base_name unless existing_names.include?(base_name.downcase)

    suffix = 2
    loop do
      candidate = "#{base_name} #{suffix}"
      return candidate unless existing_names.include?(candidate.downcase)

      suffix += 1
    end
  end

  def ensure_default_view!
    default_view = @database.database_views.find_by(default: true)
    return default_view if default_view.present?

    first_view = @database.database_views.ordered.first
    if first_view.present?
      first_view.set_as_default!
      return first_view
    end
    return nil unless policy(DatabaseView.new(database: @database, workspace: @workspace, created_by: current_user)).create?

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
