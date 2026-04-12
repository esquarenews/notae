class DbRowsController < ApplicationController
  include DatabaseTablePresentation
  include KalendariumCalendarScope
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :ensure_database_unlocked!
  before_action :set_db_row, only: %i[update destroy move duplicate restore schedule_in_kalendarium confirm_schedule_in_kalendarium]
  track_request_performance_for :create, :update

  def create
    @db_row = @database.db_rows.new(db_row_params)
    @db_row.title = "Untitled row" if @db_row.title.blank?
    seed_plan = build_new_row_seed_plan(
      date_override_property_id: params[:date_property_id],
      date_override_value: params[:date_value]
    )
    @db_row.data_json = build_row_data_json_from_seed_plan(seed_plan)
    authorize @db_row
    apply_linked_page_update!
    collapse_row_split_if_switching_context!(current_row_id: @db_row.id)

    if @db_row.errors.any?
      redirect_to database_redirect_location, alert: @db_row.errors.full_messages.to_sentence
      return
    end

    if @db_row.save
      insert_row_after_reference!(@db_row, params[:insert_after_id]) if params[:insert_after_id].present?
      seed_cells_for_row(@db_row, seed_plan: seed_plan)
      clear_row_sorting_preferences! if params[:insert_after_id].present?
      if @redirect_split_source == "row" && @redirect_split_page_id.present?
        @redirect_split_row_id ||= @db_row.id
      end
      if turbo_create_row_request?
        render turbo_stream: turbo_stream_create_row_response(@db_row)
      else
        redirect_to database_redirect_location(
          anchor: created_row_redirect_anchor(@db_row),
          highlight_row_id: highlight_new_row_id_for_response(@db_row)
        ), notice: "Row created."
      end
    else
      respond_row_create_failure(message: @db_row.errors.full_messages.to_sentence)
    end
  end

  def update
    authorize @db_row, :update?
    @db_row.assign_attributes(db_row_params)
    apply_linked_page_update!
    collapse_row_split_if_switching_context!(current_row_id: @db_row.id)
    apply_row_style_update!

    if @db_row.errors.any?
      respond_row_update_failure(anchor: "row_#{@db_row.id}", message: @db_row.errors.full_messages.to_sentence)
      return
    end

    @db_row.title = "Untitled row" if @db_row.title.blank?

    if @db_row.save
      next_row = create_next_row_requested? ? create_row_below!(@db_row) : nil

      if create_next_row_requested? && next_row.blank?
        respond_row_update_failure(anchor: "row_#{@db_row.id}", message: @db_row.errors.full_messages.to_sentence)
        return
      end

      if request.format.json?
        @database.reload
        render json: {
          id: @db_row.id,
          title: @db_row.title,
          topbar_edited_at_html: render_to_string(
            partial: "databases/topbar_edited_meta",
            formats: [ :html ],
            locals: { database: @database }
          )
        }, status: :ok
      elsif turbo_inline_row_update_request?(next_row:)
        render turbo_stream: turbo_stream_update_row_response(@db_row)
      elsif turbo_title_autosave_request?(next_row:)
        @database.reload
        render turbo_stream: [
          turbo_stream.update(
            "database_topbar_edited_at",
            partial: "databases/topbar_edited_meta",
            locals: { database: @database }
          ),
          database_flash_stream("notice", "Row updated.")
        ]
      elsif turbo_create_next_row_request?(next_row)
        render turbo_stream: turbo_stream_create_next_row_response(next_row)
      elsif next_row.present?
        close_row_split_for_row_switch!
        redirect_to database_redirect_location(
          anchor: "row_#{next_row.id}",
          highlight_row_id: highlight_new_row_id_for_response(next_row)
        ), notice: "Row updated."
      else
        redirect_to database_redirect_location(anchor: "row_#{@db_row.id}"), notice: "Row updated."
      end
    else
      respond_row_update_failure(anchor: "row_#{@db_row.id}", message: @db_row.errors.full_messages.to_sentence)
    end
  end

  def destroy
    authorize @db_row, :destroy?
    @db_row.update!(archived_at: Time.current)

    if turbo_destroy_row_request?
      render turbo_stream: turbo_stream_destroy_row_response(@db_row)
    else
      close_row_split_for_row_switch! if deleting_current_split_row?
      redirect_to database_redirect_location, notice: "Row archived."
    end
  end

  def restore
    authorize @db_row, :restore?
    @db_row.update!(archived_at: nil)
    redirect_to database_redirect_location, notice: "Row restored."
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
    clear_row_sorting_preferences! if property.blank? && ActiveModel::Type::Boolean.new.cast(params[:clear_sort])

    respond_to do |format|
      format.json do
        render json: { redirect_url: manual_order_redirect_location }, status: :ok
      end
      format.html do
        redirect_to manual_order_redirect_location, notice: "Row moved."
      end
    end
  end

  def duplicate
    authorize @db_row, :update?

    duplicated_row = duplicate_row!(@db_row)
    redirect_to database_redirect_location(anchor: "row_#{duplicated_row.id}"), notice: "Row duplicated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_location(anchor: "row_#{@db_row.id}"), alert: error.record.errors.full_messages.to_sentence
  end

  def schedule_in_kalendarium
    authorize @db_row, :update?

    unless can_prepare_tasks_project?
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}"),
                  alert: "You do not have permission to schedule tasks in Kalendarium."
      return
    end

    tasks_project = Kalendarium::TasksProjectEnsurer.new(workspace: @workspace, actor: current_user).call
    scheduling_service = Kalendarium::TaskSchedulingService.new(
      workspace: @workspace,
      row: @db_row,
      actor: current_user,
      tasks_project: tasks_project,
      busy_calendar_ids: scheduling_calendar_ids(tasks_project: tasks_project),
      visible_project_ids: [ tasks_project.id ]
    )
    candidate_result = scheduling_service.candidate_slots(limit: Kalendarium::TaskSchedulingService::DEFAULT_CANDIDATE_LIMIT)

    if candidate_result.success?
      notice_message =
        if suggested_schedule_window_start(candidate_result.slots) > scheduling_today
          "Showing the next available suggested slots in Kalendarium."
        else
          scheduling_service.suggestion_notice(slot_count: candidate_result.slots.size)
        end
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  notice: notice_message
    else
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}"), alert: candidate_result.error
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}"), alert: error.record.errors.full_messages.to_sentence
  end

  def confirm_schedule_in_kalendarium
    authorize @db_row, :update?

    unless can_prepare_tasks_project?
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  alert: "You do not have permission to schedule tasks in Kalendarium."
      return
    end

    starts_at = parse_schedule_slot_time(params[:starts_at].presence || params[:starts_at_local])
    ends_at = parse_schedule_slot_time(params[:ends_at].presence || params[:ends_at_local])
    unless starts_at.present? && ends_at.present? && ends_at > starts_at
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  alert: "That suggested slot is invalid. Choose another slot in Kalendarium."
      return
    end

    tasks_project = Kalendarium::TasksProjectEnsurer.new(workspace: @workspace, actor: current_user).call
    scheduling_service = Kalendarium::TaskSchedulingService.new(
      workspace: @workspace,
      row: @db_row,
      actor: current_user,
      tasks_project: tasks_project,
      busy_calendar_ids: scheduling_calendar_ids(tasks_project: tasks_project),
      visible_project_ids: [ tasks_project.id ]
    )
    candidate_result = scheduling_service.candidate_slots(limit: Kalendarium::TaskSchedulingService::DEFAULT_CANDIDATE_LIMIT)
    unless candidate_result.success?
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id), alert: candidate_result.error
      return
    end

    chosen_slot = candidate_result.slots.find do |slot|
      slot.starts_at.to_i == starts_at.to_i && slot.ends_at.to_i == ends_at.to_i
    end

    if chosen_slot.blank? && scheduling_service.slot_available?(starts_at:, ends_at:, manual_override: true)
      chosen_slot = Kalendarium::TaskSchedulingService::Slot.new(starts_at:, ends_at:)
    end

    if chosen_slot.blank?
      availability_error = scheduling_service.availability_error(starts_at:, ends_at:, manual_override: true)
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  alert: availability_error.presence || "That slot is no longer available. Choose another one in Kalendarium."
      return
    end

    event = scheduling_service.build_event(
      starts_at: chosen_slot.starts_at,
      ends_at: chosen_slot.ends_at,
      tasks_project: tasks_project
    )

    if event.blank?
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  alert: "The Tasks calendar could not be prepared."
      return
    end

    authorize event, :create?

    if event.save
      duration_minutes = chosen_slot.duration_minutes
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: nil),
                  notice: "Scheduled a #{duration_minutes}-minute task block in Kalendarium."
    else
      redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                  alert: event.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to schedule_redirect_location(anchor: "row_#{@db_row.id}", task_row_id: @db_row.id),
                alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
  end

  def db_row_params
    params.require(:db_row).permit(:title)
  end

  def db_row_link_params
    params.fetch(:db_row, ActionController::Parameters.new).permit(:linked_page_id, :link_action)
  end

  def db_row_style_params
    params.fetch(:db_row, ActionController::Parameters.new).permit(:style_action, :text_color)
  end

  def create_next_row_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:db_row, :create_next_row))
  end

  def title_autosave_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:db_row, :autosave_title))
  end

  def turbo_title_autosave_request?(next_row:)
    title_autosave_requested? && request.format.turbo_stream? && next_row.blank?
  end

  def turbo_inline_row_update_request?(next_row:)
    return false unless request.format.turbo_stream?
    return false unless next_row.blank?
    return false unless simple_table_render_context?
    return false if params[:split_source].to_s == "row"
    return false if title_autosave_requested?

    true
  end

  def turbo_create_next_row_request?(next_row)
    return false unless title_autosave_requested?
    return false unless request.format.turbo_stream?
    return false if next_row.blank?
    return false unless simple_table_render_context?
    return false if params[:split_source].to_s == "row"

    true
  end

  def turbo_create_row_request?
    return false unless request.format.turbo_stream?
    return false unless simple_table_render_context?
    return false if params[:split_source].to_s == "row"

    true
  end

  def set_db_row
    @db_row = policy_scope(DbRow).for_database(@database).find(params[:id])
  end

  def seed_cells_for_row(row, seed_plan: nil, assume_empty: false)
    if seed_plan.present?
      return insert_seeded_cells_for_row(row, seed_plan)
    end

    db_properties = db_properties_for_database
    return if db_properties.empty?

    property_ids = db_properties.map(&:id)
    existing_property_ids = assume_empty ? [] : row.db_cells.where(db_property_id: property_ids).pluck(:db_property_id)
    existing_lookup = existing_property_ids.each_with_object({}) { |property_id, memo| memo[property_id] = true }

    now = Time.current
    default_created_date = Date.current.iso8601
    missing_cells = db_properties.each_with_object([]) do |db_property, memo|
      next if existing_lookup[db_property.id]

      memo << {
        id: SecureRandom.uuid,
        workspace_id: @workspace.id,
        db_row_id: row.id,
        db_property_id: db_property.id,
        value_text: default_cell_value_for_property(db_property, default_created_date:),
        created_at: now,
        updated_at: now
      }
    end
    return if missing_cells.empty?

    DbCell.insert_all(missing_cells, unique_by: :index_db_cells_on_db_row_id_and_db_property_id)
  end

  def insert_seeded_cells_for_row(row, seed_plan)
    return if seed_plan.empty?

    now = Time.current
    DbCell.insert_all(
      seed_plan.map do |entry|
        {
          id: SecureRandom.uuid,
          workspace_id: @workspace.id,
          db_row_id: row.id,
          db_property_id: entry[:property].id,
          value_text: entry[:value],
          created_at: now,
          updated_at: now
        }
      end,
      unique_by: :index_db_cells_on_db_row_id_and_db_property_id
    )
  end

  def assign_date_value_to_row(row)
    date_property_id = params[:date_property_id].presence
    date_value = params[:date_value].presence
    return if date_property_id.blank? || date_value.blank?

    date_property = policy_scope(DbProperty).for_database(@database).find_by(id: date_property_id, property_type: :date)
    return if date_property.blank?

    existing_cell = row.db_cells.find_by(db_property_id: date_property.id, workspace_id: @workspace.id)
    if existing_cell.present?
      return if existing_cell.value_text == date_value

      existing_cell.update_columns(value_text: date_value, updated_at: Time.current)
      return
    end

    now = Time.current
    DbCell.insert_all(
      [
        {
          id: SecureRandom.uuid,
          workspace_id: @workspace.id,
          db_row_id: row.id,
          db_property_id: date_property.id,
          value_text: date_value,
          created_at: now,
          updated_at: now
        }
      ],
      unique_by: :index_db_cells_on_db_row_id_and_db_property_id
    )
  end

  def database_redirect_location(anchor: nil, highlight_row_id: nil, task_row_id: :__preserve__)
    split_page_id = @clear_split_page ? nil : (@redirect_split_page_id || params[:split_page_id].presence)
    split_source = @clear_split_page ? nil : (@redirect_split_source || params[:split_source].presence)
    split_row_id = @clear_split_page ? nil : (@redirect_split_row_id || params[:split_row_id].presence)
    split_panel = @redirect_split_panel || params[:split_panel].presence
    task_row_id = params[:task_row_id].presence if task_row_id == :__preserve__

    path_params = {
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      sort_property_id: @clear_sorting ? nil : params[:sort_property_id].presence,
      sort_direction: @clear_sorting ? nil : params[:sort_direction].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      rows_page: params[:rows_page].presence,
      view_settings: params[:view_settings].presence,
      actions_menu: params[:actions_menu].presence,
      options_menu: params[:options_menu].presence,
      split_panel: split_panel,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id,
      task_row_id: task_row_id,
      highlight_row_id: highlight_row_id.presence || params[:highlight_row_id].presence
    }.compact
    path_params[:anchor] = anchor if anchor.present?
    database_path(path_params)
  end

  def manual_order_redirect_location
    database_path(
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: params[:view_id].presence,
      month: params[:month].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      rows_page: params[:rows_page].presence,
      options_menu: params[:options_menu].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence,
      task_row_id: params[:task_row_id].presence
    )
  end

  def schedule_redirect_location(anchor: nil, task_row_id: :__preserve__)
    @clear_split_page = true
    @redirect_split_panel = "kalendarium"
    database_redirect_location(anchor:, task_row_id:)
  end

  def scheduling_calendar_ids(tasks_project:)
    selected_provider_calendar_ids_for_workspace + [ tasks_project.kalendarium_calendar_id.to_s ]
  end

  def suggested_schedule_window_start(slots)
    first_slot = slots.first
    return scheduling_today if first_slot.blank?

    first_slot_date = first_slot.starts_at.in_time_zone(current_user.time_zone).to_date
    return scheduling_today if first_slot_date <= scheduling_today + 6.days

    first_slot_date
  end

  def scheduling_today
    @scheduling_today ||= Time.current.in_time_zone(current_user.time_zone).to_date
  end

  def apply_linked_page_update!
    payload = db_row_link_params
    action = payload[:link_action].to_s

    if action == "create_page"
      linked_page = create_linked_page_for_row
      @db_row.linked_page = linked_page if linked_page.present?
      @redirect_split_page_id = linked_page&.id
      @redirect_split_source = "row"
      @redirect_split_row_id = @db_row.id
      return
    end

    return unless payload.key?(:linked_page_id)

    resolved_page = resolve_linkable_page(payload[:linked_page_id])
    return if resolved_page == :invalid

    @db_row.linked_page = resolved_page
    @clear_split_page = true if resolved_page.nil?
    @redirect_split_page_id = resolved_page&.id
    @redirect_split_source = "row" if resolved_page.present?
    @redirect_split_row_id = @db_row.id if resolved_page.present?
  end

  def apply_row_style_update!
    payload = db_row_style_params
    return if payload[:style_action].blank?

    @db_row.apply_row_style_action!(action: payload[:style_action], text_color: payload[:text_color])
  end

  def create_linked_page_for_row
    title = @db_row.title.presence || "Untitled row"
    page = @workspace.pages.new(title: title, created_by: current_user)
    unless policy(page).create?
      @db_row.errors.add(:base, "You are not authorized to create Notarum in this workspace.")
      return nil
    end

    return page if page.save

    @db_row.errors.add(:base, page.errors.full_messages.to_sentence)
    nil
  end

  def resolve_linkable_page(raw_id)
    candidate_id = raw_id.to_s.strip
    return nil if candidate_id.blank?

    linked_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: candidate_id)
    return linked_page if linked_page.present?

    @db_row.errors.add(:linked_page_id, "must reference an accessible page in this workspace")
    :invalid
  end

  def insert_row_after_reference!(row, reference_row_id)
    reference = policy_scope(DbRow).for_database(@database).active.find_by(id: reference_row_id)
    return if reference.blank?

    ordered_rows = policy_scope(DbRow).for_database(@database).active.ordered.to_a
    reference_index = ordered_rows.index { |candidate| candidate.id == reference.id }
    return if reference_index.nil?

    next_row = ordered_rows[(reference_index + 1)..]&.find { |candidate| candidate.id != row.id }
    target_position = suggested_insert_position_after(reference:, next_row:)
    if target_position.present?
      row.update_columns(position: target_position, updated_at: Time.current) if row.position != target_position
      return
    end

    # Fallback to full normalization when no sparse position remains.
    DbRows::MoveService.call(
      row: row,
      database: @database,
      workspace: @workspace,
      property: nil,
      target_value: nil,
      target_index: reference_index + 1
    )
  end

  def collapse_row_split_if_switching_context!(current_row_id:)
    return if @redirect_split_page_id.present? || @redirect_split_source.present?
    return unless params[:split_source].to_s == "row"

    split_row_id = params[:split_row_id].to_s.presence
    return if split_row_id.blank?
    return if current_row_id.present? && split_row_id == current_row_id.to_s

    @clear_split_page = true
    @redirect_split_page_id = nil
    @redirect_split_source = nil
    @redirect_split_row_id = nil
  end

  def close_row_split_for_row_switch!
    return unless params[:split_source].to_s == "row"

    @clear_split_page = true
    @redirect_split_page_id = nil
    @redirect_split_source = nil
    @redirect_split_row_id = nil
  end

  def create_row_below!(reference_row)
    seed_plan = build_new_row_seed_plan
    row_candidate = @database.db_rows.new(
      workspace: @workspace,
      title: "Untitled row",
      data_json: build_row_data_json_from_seed_plan(seed_plan)
    )
    unless policy(row_candidate).create?
      @db_row.errors.add(:base, "You are not authorized to create rows in this grid.")
      return nil
    end

    unless row_candidate.save
      @db_row.errors.add(:base, row_candidate.errors.full_messages.to_sentence)
      return nil
    end

    insert_row_after_reference!(row_candidate, reference_row.id)
    seed_cells_for_row(row_candidate, seed_plan: seed_plan)
    clear_row_sorting_preferences!
    row_candidate
  end

  def turbo_stream_create_next_row_response(next_row)
    load_table_row_render_context!(rows: [ @db_row, next_row ])
    active_row_count = policy_scope(DbRow).for_database(@database).active.count

    [
      turbo_stream.update(
        "database_topbar_edited_at",
        partial: "databases/topbar_edited_meta",
        locals: { database: @database.reload }
      ),
      turbo_stream.update(
        "database_row_count",
        partial: "databases/row_count_meta",
        locals: { row_count: active_row_count }
      ),
      turbo_stream.replace(
        "row_#{@db_row.id}",
        partial: "databases/table_row",
        locals: table_row_locals(row: @db_row)
      ),
      turbo_stream.after(
        "row_#{@db_row.id}",
        partial: "databases/table_row",
        locals: table_row_locals(row: next_row, autofocus_title: true, highlight_row_id: next_row.id)
      ),
      turbo_stream.update(
        "database_table_placeholders",
        partial: "databases/table_placeholders",
        locals: {
          visible_properties: @visible_db_properties,
          placeholder_count: [ 6 - active_row_count, 0 ].max
        }
      ),
      database_flash_stream("notice", "Row updated.")
    ]
  end

  def turbo_stream_create_row_response(row)
    load_table_row_render_context!(rows: [ row ])
    active_row_count = policy_scope(DbRow).for_database(@database).active.count
    insertion_target = table_row_insertion_target_for_response
    insertion_stream =
      if insertion_target.present?
        turbo_stream.after(
          "row_#{insertion_target.id}",
          partial: "databases/table_row",
          locals: table_row_locals(row: row, autofocus_title: true, highlight_row_id: row.id)
        )
      else
        turbo_stream.append(
          "database_table_rows",
          partial: "databases/table_row",
          locals: table_row_locals(row: row, autofocus_title: true, highlight_row_id: row.id)
        )
      end

    [
      turbo_stream.update(
        "database_topbar_edited_at",
        partial: "databases/topbar_edited_meta",
        locals: { database: @database.reload }
      ),
      turbo_stream.update(
        "database_row_count",
        partial: "databases/row_count_meta",
        locals: { row_count: active_row_count }
      ),
      insertion_stream,
      turbo_stream.update(
        "database_table_placeholders",
        partial: "databases/table_placeholders",
        locals: {
          visible_properties: @visible_db_properties,
          placeholder_count: [ 6 - active_row_count, 0 ].max
        }
      ),
      turbo_stream.replace(
        "database_flash_messages",
        partial: "shared/flash_messages",
        locals: {
          flash_messages: [ [ "notice", "Row created." ] ],
          flash_dom_id: "database_flash_messages",
          flash_host_class: "notae-db-inline-flash-host"
        }
      )
    ]
  end

  def turbo_stream_destroy_row_response(row)
    load_table_row_render_context!(rows: [])
    active_row_count = policy_scope(DbRow).for_database(@database).active.count

    [
      turbo_stream.update(
        "database_row_count",
        partial: "databases/row_count_meta",
        locals: { row_count: active_row_count }
      ),
      turbo_stream.remove("row_#{row.id}"),
      turbo_stream.update(
        "database_table_placeholders",
        partial: "databases/table_placeholders",
        locals: {
          visible_properties: @visible_db_properties,
          placeholder_count: [ 6 - active_row_count, 0 ].max
        }
      ),
      turbo_stream.replace(
        "database_flash_messages",
        partial: "shared/flash_messages",
        locals: {
          flash_messages: [ [ "notice", "Row archived." ] ],
          flash_dom_id: "database_flash_messages",
          flash_host_class: "notae-db-inline-flash-host"
        }
      )
    ]
  end

  def turbo_stream_update_row_response(row)
    load_table_row_render_context!(rows: [ row ])

    [
      turbo_stream.update(
        "database_topbar_edited_at",
        partial: "databases/topbar_edited_meta",
        locals: { database: @database.reload }
      ),
      turbo_stream.replace(
        "row_#{row.id}",
        partial: "databases/table_row",
        locals: table_row_locals(row: row)
      ),
      database_flash_stream("notice", "Row updated.")
    ]
  end

  def table_row_insertion_target_for_response
    reference_id = params[:insert_after_id].to_s.presence
    return nil if reference_id.blank?

    policy_scope(DbRow).for_database(@database).active.find_by(id: reference_id)
  end

  def created_row_redirect_anchor(row)
    return nil unless simple_table_render_context?

    "row_#{row.id}"
  end

  def simple_table_render_context?
    current_view = current_database_view_for_response
    view_config = current_view&.config_json.to_h || {}

    return false unless (current_view&.view_type || "table") == "table"
    return false if params[:sort_property_id].present? || params[:filter_property_id].present?
    return false if view_config["sort_property_id"].present? || view_config["filter_property_id"].present?

    true
  end

  def respond_row_create_failure(message:)
    if request.format.turbo_stream? && simple_table_render_context?
      render turbo_stream: database_flash_stream("alert", message), status: :unprocessable_entity
    else
      redirect_to database_redirect_location, alert: message
    end
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
      policy_scope(DbCell)
        .for_database(@database)
        .where(db_row_id: rows.map(&:id), db_property_id: property_ids)
        .to_a
        .index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    end
    @select_options_by_property = build_select_options_by_property_for_rows(properties: @visible_db_properties)
  end

  def build_select_options_by_property_for_rows(properties:)
    properties.select(&:select?).each_with_object({}) do |property, options|
      values = if task_status_property?(property)
        DatabaseTablePresentation::TASK_STATUS_OPTIONS.dup
      else
        []
      end
      seen = values.each_with_object({}) { |value, memo| memo[value] = true }

      policy_scope(DbCell)
        .for_database(@database)
        .where(db_property_id: property.id)
        .where.not(value_text: [ nil, "" ])
        .distinct
        .order(:value_text)
        .pluck(:value_text)
        .each do |value|
          normalized = task_status_property?(property) ? normalize_task_status_value(value) : value.to_s.strip
          next if normalized.blank? || seen.key?(normalized)

          seen[normalized] = true
          values << normalized
        end

      options[property.id] = task_status_property?(property) ? values : values.sort
    end
  end

  def table_row_locals(row:, autofocus_title: false, highlight_row_id: params[:highlight_row_id].presence)
    {
      row: row,
      workspace: @workspace,
      database: @database,
      current_view: @current_view,
      row_params: table_row_params,
      visible_properties: @visible_db_properties,
      cells_by_key: @cells_by_key,
      can_create_rows: policy(DbRow.new(database: @database, workspace: @workspace)).create? && !@database.locked?,
      row_color_options: row_color_options,
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

  def highlight_new_row_id_for_response(row)
    return unless row.title.to_s == "Untitled row"
    return unless table_view_response?

    row.id
  end

  def table_view_response?
    (current_database_view_for_response&.view_type || "table") == "table"
  end

  def turbo_destroy_row_request?
    return false unless request.format.turbo_stream?
    return false unless table_view_response?
    return false if deleting_current_split_row?

    true
  end

  def deleting_current_split_row?
    params[:split_source].to_s == "row" && params[:split_row_id].to_s == @db_row.id.to_s
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

  def duplicate_row!(row)
    duplicated = nil

    ActiveRecord::Base.transaction do
      duplicated = @database.db_rows.create!(
        workspace: @workspace,
        title: row.title.presence || "Untitled row",
        linked_page_id: row.linked_page_id,
        data_json: row.style_metadata
      )

      row.db_cells.includes(:db_property).find_each do |source_cell|
        duplicated.db_cells.create!(
          workspace: @workspace,
          db_property: source_cell.db_property,
          value_text: source_cell.value_text
        )
      end

      seed_cells_for_row(duplicated)
      duplicated.sync_data_from_cells!
      insert_row_after_reference!(duplicated, row.id)
    end

    if duplicated.linked_page_id.present?
      @redirect_split_page_id = duplicated.linked_page_id
      @redirect_split_source = "row"
      @redirect_split_row_id = duplicated.id
    end

    duplicated
  end

  def clear_row_sorting_preferences!
    @clear_sorting = true
    return if params[:view_id].blank?

    view = policy_scope(DatabaseView).for_database(@database).find_by(id: params[:view_id])
    return if view.blank?
    return unless policy(view).update?

    config = view.config_json.to_h.deep_dup
    changed = false
    changed = config.delete("sort_property_id").present? || changed
    changed = config.delete("sort_direction").present? || changed
    view.update!(config_json: config) if changed
  end

  def default_cell_value_for_property(property, default_created_date: Date.current.iso8601)
    return default_created_date if date_created_property?(property)
    return "not started" if task_status_property?(property)

    ""
  end

  def build_new_row_seed_plan(date_override_property_id: nil, date_override_value: nil)
    default_created_date = Date.current.iso8601
    override_id = date_override_property_id.to_s.presence
    override_value = date_override_value.to_s.presence

    db_properties_for_database.map do |property|
      value =
        if override_id.present? && override_value.present? && property.date? && property.id.to_s == override_id
          override_value
        else
          default_cell_value_for_property(property, default_created_date:)
        end

      {
        property: property,
        value: value
      }
    end
  end

  def build_row_data_json_from_seed_plan(seed_plan, style_payload: {})
    seed_plan.each_with_object({}) do |entry, data|
      key = entry[:property].name.to_s.strip
      next if key.blank?

      data[key] = entry[:value].to_s
    end.merge(style_payload)
  end

  def date_created_property?(property)
    property.date? && property.name.to_s.strip.casecmp("date created").zero?
  end

  def sync_row_cache_after_seed!(row)
    row.sync_data_from_cells!
  end

  def db_properties_for_database
    @db_properties_for_database ||= policy_scope(DbProperty).for_database(@database).ordered.to_a
  end

  def suggested_insert_position_after(reference:, next_row:)
    return reference.position + DbRow::POSITION_GAP if next_row.blank?

    lower_bound = reference.position.to_i
    upper_bound = next_row.position.to_i
    gap = upper_bound - lower_bound
    return nil if gap <= 1

    candidate = lower_bound + (gap / 2)
    return nil if candidate <= lower_bound || candidate >= upper_bound

    candidate
  end

  def ensure_database_unlocked!
    return unless @database.locked?

    redirect_to database_redirect_location, alert: "Grid is locked. Unlock to make changes."
  end

  def can_prepare_tasks_project?
    existing_project =
      policy_scope(KalendariumProject).for_workspace(@workspace).find_by(slug: Kalendarium::TasksProjectEnsurer::PROJECT_SLUG) ||
      policy_scope(KalendariumProject).for_workspace(@workspace).where("LOWER(name) = ?", Kalendarium::TasksProjectEnsurer::PROJECT_NAME.downcase).order(:created_at).first
    return true if existing_project.present?

    policy(
      KalendariumProject.new(
        workspace: @workspace,
        created_by: current_user,
        name: Kalendarium::TasksProjectEnsurer::PROJECT_NAME,
        slug: Kalendarium::TasksProjectEnsurer::PROJECT_SLUG,
        color_hex: Kalendarium::TasksProjectEnsurer::PROJECT_COLOR
      )
    ).create?
  end

  def parse_schedule_slot_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def respond_row_update_failure(anchor:, message:)
    respond_to do |format|
      format.json { render json: { error: message }, status: :unprocessable_entity }
      format.turbo_stream { render plain: message, status: :unprocessable_entity }
      format.html { redirect_to database_redirect_location(anchor:), alert: message }
    end
  end
end
