class DatabasesController < ApplicationController
  include DatabaseTablePresentation
  include KalendariumCalendarScope
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database, only: %i[show update duplicate archive export_csv export_gantt_pdf export_graph_pdf gantt_embed graph_embed permissions move_workspace taskify statsify stats_setup stats_entries save_as_template apply_template kanbanize panel]
  before_action :set_archived_database, only: %i[restore destroy]
  track_request_performance_for :show, :update

  COVER_SHIFT_STEP = 10
  FILTER_OPERATORS = %w[eq neq before after].freeze
  TASK_TEMPLATE_PROPERTIES = [
    [ "Status", "select" ],
    [ "Date created", "date" ],
    [ "Due date", "date" ],
    [ "Notes", "text" ]
  ].freeze
  TASK_TEMPLATE_PROPERTY_TYPES = TASK_TEMPLATE_PROPERTIES.each_with_object({}) do |(name, property_type), index|
    index[name.downcase] = property_type
  end.freeze

  def show
    authorize @database
    ensure_tab_shell_page!
    ensure_default_view!
    @page_tabs = resolve_page_tabs
    @page_title_page = @database.linked_page&.parent_page
    @can_update_page_title_page = @page_title_page.present? && policy(@page_title_page).update?
    @can_create_tab_page =
      if @page_tabs.group_page.present?
        policy(Page.new(workspace: @workspace, created_by: current_user, parent_page: @page_tabs.group_page, title: "New tab")).create?
      else
        false
      end

    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @can_apply_tasks_template = tasks_template_convertible?(properties: @db_properties)
    @can_apply_stats_template = stats_template_convertible?(properties: @db_properties)
    @tasks_template_ready = tasks_template_ready?(properties: @db_properties)
    @stats_template_active = Databases::StatsTemplateService.stats_database?(@database)
    @database_templates = policy_scope(DatabaseTemplate).for_workspace(@workspace).recent_first.limit(20).to_a
    @current_database_template_label = current_database_template_label
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @primary_database_view = resolve_primary_database_view
    @view_type = @current_view&.view_type || "table"
    @view_config = @current_view&.config_json.to_h || {}
    resolve_filter_and_sort_settings!
    prepare_stats_template_data! if @stats_template_active
    row_query = resolve_row_query
    @rows = row_query.rows
    @row_count = row_query.total_count
    @rows_page = row_query.page
    @rows_per_page = row_query.per_page
    @rows_total_pages = row_query.total_pages
    @rows_paginated = row_query.paginated?
    @split_page = resolve_split_page
    @kalendarium_split_active = params[:split_panel].to_s == "kalendarium"
    @gantt_split_active = params[:split_panel].to_s == "gantt"
    @graph_split_active = params[:split_panel].to_s == "graph"
    @kalendarium_split_project = resolve_tasks_project_for_split if @kalendarium_split_active
    @kalendarium_task_row = resolve_kalendarium_task_row if @kalendarium_split_active
    @kalendarium_split_window_start = resolve_kalendarium_split_window_start if @kalendarium_split_active
    required_property_ids = required_property_ids_for_cell_load
    @cells = load_cells_for_rows_and_properties(property_ids: required_property_ids)
    @cells_by_key = @cells.index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    schedule_missing_cells_backfill(property_ids: required_property_ids, loaded_cell_count: @cells.size)
    @select_options_by_property = build_select_options_by_property
    @backlinks =
      if @database.linked_page.present?
        policy_scope(PageLink).for_target(@database.linked_page).includes(source_page: :linked_database).order(created_at: :desc)
      else
        []
      end

    apply_row_filter!
    sort_rows!
    prepare_board_view_data!
    prepare_calendar_view_data!
    prepare_gantt_split_data!
    prepare_graph_split_data!

    @new_database = Database.new
    @new_property = DbProperty.new
    @new_row = DbRow.new
    @new_database_view = DatabaseView.new
    @database_favorite = policy_scope(Favorite).for_workspace(@workspace).for_user(current_user).find_by(favoritable: @database)
  end

  def panel
    authorize @database, :show?

    case params[:panel].to_s
    when "comments"
      return head :forbidden if @database.locked?

      prepare_database_comments_panel!
      render partial: "databases/comments_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               can_comment_on_database: @can_comment_on_database,
               new_database_comment: @new_database_comment,
               database_comments: @database_comments,
               view_params: database_panel_view_params
             }
    when "options"
      prepare_database_options_panel!
      render partial: "databases/options_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               can_manage_database_permissions: policy(@database).permissions?,
               memberships: @memberships,
               shared_user_ids: @shared_user_ids,
               view_params: database_panel_view_params,
               view_link: database_panel_view_link,
               archived_rows: @archived_rows,
               can_create_database: policy(Database.new(workspace: @workspace, name: "Untitled grid")).create?,
               share_links: @database_share_links,
               can_move_database: @can_move_database,
               move_workspace_options: @move_workspace_options
             }
    when "actions"
      prepare_database_actions_panel!
      return head :not_found if @current_view.blank?

      render partial: "databases/actions_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               current_view: @current_view,
               new_database_view: @new_database_view,
               view_params: database_panel_view_params,
               view_link: database_panel_view_link,
               can_manage_database_permissions: policy(@database).permissions?,
               can_edit_database: policy(@database).update? && !@database.locked?,
               can_update_view: policy(@current_view).update? && !@database.locked?,
               can_create_database: policy(Database.new(workspace: @workspace, name: "Untitled grid")).create?,
               can_archive_database: policy(@database).archive?,
               page_search_url: workspace_document_targets_path(workspace_slug: @workspace.slug, kind: "page")
             }
    when "view_settings"
      prepare_database_view_settings_panel!
      return head :not_found if @current_view.blank?

      render partial: "databases/view_settings_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               current_view: @current_view,
               view_params: database_panel_view_params,
               can_manage_database_permissions: policy(@database).permissions?,
               can_edit_database: policy(@database).update? && !@database.locked?,
               can_update_view: policy(@current_view).update? && !@database.locked?
             }
    when "row_menu"
      return head :forbidden if @database.locked?

      prepare_database_row_menu_panel!
      render partial: "databases/row_context_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               row: @row,
               row_update_path: database_db_row_path(
                 database_row_menu_params.merge(
                   workspace_slug: @workspace.slug,
                   database_id: @database.id,
                   id: @row.id
                 )
               ),
               row_params: database_row_menu_params,
               row_color_options: row_color_options,
               row_can_destroy: policy(@row).destroy? && !@database.locked?,
               linked_page: @row.linked_page,
               row_is_bold: @row.row_bold?,
               row_is_italic: @row.row_italic?,
               row_text_color: @row.row_text_color,
               row_background_color: @row.row_background_color
             }
    when "row_link_chooser"
      return head :forbidden if @database.locked?

      prepare_database_row_menu_panel!
      render partial: "databases/row_link_chooser_panel",
             locals: {
               row: @row,
               row_update_path: database_db_row_path(
                 database_row_menu_params.merge(
                   workspace_slug: @workspace.slug,
                   database_id: @database.id,
                   id: @row.id
                 )
               ),
               linked_page: @row.linked_page,
               page_search_url: workspace_document_targets_path(workspace_slug: @workspace.slug, kind: "page")
             }
    when "column_menu"
      return head :forbidden if @database.locked?

      prepare_database_column_menu_panel!
      render partial: "databases/column_context_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               db_property: @db_property,
               row_params: database_row_menu_params,
               row_color_options: row_color_options
             }
    when "name_column_menu"
      return head :forbidden if @database.locked?

      authorize @database, :update?
      render partial: "databases/name_column_context_menu_body",
             locals: {
               workspace: @workspace,
               database: @database,
               row_params: database_row_menu_params,
               row_color_options: row_color_options
             }
    else
      head :not_found
    end
  end

  def create
    @database = @workspace.databases.new(database_params)
    @database.created_by = current_user
    template = normalize_template(params[:template])
    apply_template_default_name!(template)
    apply_quick_create_name!
    linked_tab_parent = create_tab_parent_page
    linked_tab_title = create_tab_title
    authorize @database
    authorize_linked_tab_page!(linked_tab_parent, linked_tab_title)

    ActiveRecord::Base.transaction do
      @database.save!
      Databases::EnsureLinkedPageService.call(
        database: @database,
        actor: current_user,
        parent_page: linked_tab_parent,
        title: linked_tab_title
      )
      table_view = ensure_default_view!
      apply_template!(template, table_view:)
      log_database_audit_event!(action: "create", kind: "database_created")
    end

    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), notice: "Grid created."
  rescue ActiveRecord::RecordInvalid => error
    message = @database.errors.full_messages.to_sentence.presence || error.record.errors.full_messages.to_sentence
    redirect_to workspace_path(@workspace.slug), alert: message
  end

  def taskify
    authorize @database, :update?

    if @database.locked?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: "Grid is locked. Unlock to make changes."
      return
    end

    unless tasks_template_convertible?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id),
                  alert: "This grid already has custom fields. Open a blank grid or new tab before using the Tasks template."
      return
    end

    table_view = nil

    ActiveRecord::Base.transaction do
      table_view = resolve_or_create_table_view!
      build_tasks_template!(table_view:)
      @database.update!(database_template: nil, applied_template_name: "Tasks")
      log_database_audit_event!(action: "update", kind: "database_taskified")
    end

    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: table_view.id),
                notice: "Switched to Tasks view."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id),
                alert: error.record.errors.full_messages.to_sentence
  end

  def statsify
    authorize @database, :update?

    if @database.locked?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: "Grid is locked. Unlock to make changes."
      return
    end

    unless stats_template_convertible?
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id),
                  alert: "This grid already has custom fields. Open a blank grid or new tab before using the Stats template."
      return
    end

    table_view = nil

    ActiveRecord::Base.transaction do
      table_view = resolve_or_create_table_view!
      Databases::StatsTemplateService.apply!(database: @database, table_view:)
      log_database_audit_event!(action: "update", kind: "database_stats_template_applied")
    end

    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: table_view.id, stats_mode: "setup"),
                notice: "Switched to Stats view."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id),
                alert: error.record.errors.full_messages.to_sentence
  end

  def stats_setup
    authorize @database, :update?

    if @database.locked?
      redirect_to database_redirect_path, alert: "Grid is locked. Unlock to make changes."
      return
    end

    Databases::StatsTemplateService.save_setup!(
      database: @database,
      definition_params: stats_setup_params.fetch("definitions", {}),
      new_definition_params: stats_setup_params.fetch("new_definition", {}),
      archive_definition_id: params[:archive_stat_id]
    )

    redirect_to database_path(database_panel_view_params.merge(stats_mode: "setup", stats_date: params[:stats_date].presence)),
                notice: "Stats setup saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(database_panel_view_params.merge(stats_mode: "setup", stats_date: params[:stats_date].presence)),
                alert: error.record.errors.full_messages.to_sentence
  end

  def stats_entries
    authorize @database, :update?

    if @database.locked?
      redirect_to database_redirect_path, alert: "Grid is locked. Unlock to make changes."
      return
    end

    selected_date = Databases::StatsTemplateService.selected_date(params[:stats_date], today: Time.zone.today)
    Databases::StatsTemplateService.save_entries!(
      database: @database,
      date: selected_date,
      entry_params: stats_entries_params.fetch("entries", {})
    )

    redirect_to database_path(database_panel_view_params.merge(stats_date: selected_date.iso8601, stats_mode: "report")),
                notice: "Stats saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_path(database_panel_view_params.merge(stats_date: params[:stats_date].presence, stats_mode: "report")),
                alert: error.record.errors.full_messages.to_sentence
  end

  def save_as_template
    authorize @database, :show?

    template_record = DatabaseTemplate.new(
      workspace: @workspace,
      database: @database,
      created_by: current_user,
      name: database_template_name,
      snapshot_json: {}
    )
    authorize template_record, :create?

    Databases::CreateTemplateService.call(
      database: @database,
      current_view: resolve_template_source_view,
      created_by: current_user,
      name: database_template_name
    )

    redirect_to database_redirect_path, notice: "Template saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_path, alert: error.record.errors.full_messages.to_sentence
  end

  def apply_template
    authorize @database, :update?

    if @database.locked?
      redirect_to database_redirect_path, alert: "Grid is locked. Unlock to make changes."
      return
    end

    template = policy_scope(DatabaseTemplate).for_workspace(@workspace).find(params[:template_id])
    authorize template, :apply?

    result = Databases::ApplyTemplateService.call(
      database: @database,
      template: template,
      created_by: current_user
    )

    log_database_audit_event!(
      action: "update",
      kind: "database_template_applied",
      database_template_id: template.id,
      template_name: template.name
    )

    redirect_to database_path(database_panel_view_params.merge(view_id: result.view&.id)), notice: "#{template.name} template applied."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_path, alert: error.record.errors.full_messages.to_sentence
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

  def move_workspace
    authorize @database, :move_workspace?
    target_workspace = move_target_workspace!
    authorize Database.new(workspace: target_workspace, name: @database.name), :create?

    Documents::WorkspaceMoveService.call(record: @database, target_workspace:, actor: current_user)

    redirect_to database_path(workspace_slug: target_workspace.slug, id: @database.id), notice: "Grid moved to #{target_workspace.name}."
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound, Documents::WorkspaceMoveService::Error, ActiveRecord::RecordInvalid => error
    redirect_to database_redirect_path, alert: error.message
  end

  def update
    authorize @database, :update?

    if @database.locked? && !unlocking_database_request?
      @database.errors.add(:base, "Grid is locked. Unlock to make changes.")
    else
      @database.assign_attributes(database_update_params)
      apply_name_column_style_update!
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

  def export_gantt_pdf
    authorize @database, :show?

    prepare_gantt_export_context!
    send_data Databases::GanttPdfExportService.call(database: @database, gantt_data: @gantt_split).pdf,
              filename: "#{@database.name.parameterize.presence || "gantt"}-gantt.pdf",
              type: "application/pdf",
              disposition: "attachment"
  end

  def export_graph_pdf
    authorize @database, :show?

    prepare_graph_export_context!
    send_data Databases::GraphPdfExportService.call(database: @database, graph_data: @graph_split).pdf,
              filename: "#{@database.name.parameterize.presence || "graph"}-graph.pdf",
              type: "application/pdf",
              disposition: "attachment"
  end

  def gantt_embed
    authorize @database, :show?

    prepare_gantt_export_context!
    @gantt_embed_view_params = database_panel_view_params
    render :gantt_embed, layout: false
  end

  def graph_embed
    authorize @database, :show?

    prepare_graph_export_context!
    @graph_embed_view_params = database_panel_view_params
    render :graph_embed, layout: false
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
    params.require(:database).permit(:name, :parent_page_id, :tab_title).except(:parent_page_id, :tab_title)
  end

  def create_tab_parent_page
    parent_page_id = params.dig(:database, :parent_page_id).to_s.strip
    return nil if parent_page_id.blank?

    parent_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: parent_page_id)
    if parent_page.present?
      Databases::EnsureLinkedPageService.call(database: parent_page.linked_database, actor: current_user) if parent_page.linked_database.present?
      return parent_page.reload
    end

    @database.errors.add(:base, "The selected tab group could not be found.")
    raise ActiveRecord::RecordInvalid, @database
  end

  def create_tab_title
    params.dig(:database, :tab_title).to_s.strip.presence
  end

  def authorize_linked_tab_page!(parent_page, title)
    return if parent_page.blank?

    tab_page = Page.new(
      workspace: @workspace,
      created_by: current_user,
      parent_page: parent_page,
      title: title.presence || @database.name
    )
    authorize tab_page, :create?
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

  def database_style_params
    params.fetch(:database, ActionController::Parameters.new).permit(:style_action, :text_color, :background_color)
  end

  def database_link_params
    params.fetch(:database, ActionController::Parameters.new).permit(:linked_page_id, :linked_page_action)
  end

  def database_header_params
    params.fetch(:database, ActionController::Parameters.new)
          .permit(:icon, :icon_action, :cover_action, :cover_shift, :cover_focal_y, :cover_image, :cover_preset_key, :cover_asset_id, :cover_remote_id, :description_action, :description)
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
    CoverAssets::ApplyService.call(record: @database, workspace: @workspace, user: current_user, payload:)
  end

  def apply_description_update!(payload)
    case payload[:description_action]
    when "set"
      @database.description = payload[:description].to_s.strip.presence
    when "clear"
      @database.description = nil
    end
  end

  def apply_name_column_style_update!
    payload = database_style_params
    return if payload[:style_action].blank?

    @database.apply_name_column_style_action!(
      action: payload[:style_action],
      text_color: payload[:text_color],
      background_color: payload[:background_color]
    )
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
    @rows
  end

  def resolve_current_view
    view_id = params[:view_id].presence
    return @database_views.find { |view| view.id.to_s == view_id } if view_id

    @database_views.find(&:default?) || @database_views.first
  end

  def resolve_primary_database_view
    template_view_type = @database.database_template&.snapshot_json&.dig("view", "view_type").to_s
    if template_view_type.present?
      template_view = @database_views.find { |view| view.view_type == template_view_type }
      return template_view if template_view.present?
    end

    @database_views.find { |view| view.view_type == "table" } ||
      @database_views.find(&:default?) ||
      @database_views.first
  end

  def ensure_tab_shell_page!
    Databases::EnsureLinkedPageService.call(database: @database, actor: current_user)
  end

  def resolve_filter_and_sort_settings!
    sort_property_id = params[:sort_property_id].presence || @view_config["sort_property_id"]
    filter_property_id = params[:filter_property_id].presence || @view_config["filter_property_id"]
    conditional_color_property_id = params[:conditional_color_property_id].presence || @view_config["conditional_color_property_id"]

    @sort_by_name = sort_property_id.to_s == DatabaseView::NAME_SORT_KEY
    @sort_property = @sort_by_name ? nil : @db_properties.find { |property| property.id.to_s == sort_property_id.to_s }
    configured_direction = params[:sort_direction].presence || @view_config["sort_direction"]
    @sort_direction = configured_direction == "desc" ? "desc" : "asc"
    configured_sort_mode = params[:sort_mode].presence || @view_config["sort_mode"]
    @sort_mode = DatabaseView::SORT_MODES.include?(configured_sort_mode.to_s) ? configured_sort_mode.to_s : "standard"

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
    @rows
  end

  def prepare_board_view_data!
    return unless @view_type == "board"

    @board_columns = []
    return if @board_group_property.blank?

    grouped_rows = Hash.new { |hash, key| hash[key] = [] }
    @rows.each do |row|
      grouped_rows[board_group_value_for(row)] << row
    end

    configured_values = select_options_for(@board_group_property)
    extra_values = grouped_rows.keys.compact.reject(&:blank?).reject { |value| configured_values.include?(value) }
    ordered_values = configured_values.dup
    ordered_values.concat(extra_values.sort)

    @board_columns << { value: nil, label: "Unassigned", rows: grouped_rows[nil] }
    ordered_values.each do |value|
      @board_columns << { value: value, label: board_group_label_for(value), rows: grouped_rows[value] }
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

  def prepare_gantt_split_data!
    return unless @gantt_split_active

    @gantt_split_data = Databases::GanttChartDataBuilder.new(
      rows: @rows,
      db_properties: @db_properties,
      cells_by_key: @cells_by_key,
      view_config: @view_config
    ).call
  end

  def prepare_graph_split_data!
    return unless @graph_split_active

    graph_rows = Databases::RowWindowQueryService.new(
      scope: policy_scope(DbRow).for_database(@database).active,
      sort_property: @sort_property,
      sort_by_title: @sort_by_name,
      sort_direction: @sort_direction,
      sort_mode: @sort_mode,
      filter_property: @filter_property,
      filter_value: @filter_value,
      filter_operator: @filter_operator,
      view_type: "graph",
      page: 1
    ).call.rows
    graph_cells_by_key = load_chart_export_cells(rows: graph_rows, properties: @visible_db_properties)

    @graph_split_data = Databases::GraphChartDataBuilder.new(
      rows: graph_rows,
      db_properties: @visible_db_properties,
      cells_by_key: graph_cells_by_key,
      view_config: @view_config
    ).call
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

  def build_select_options_by_property
    properties = @visible_db_properties || @db_properties
    build_select_options_lookup(database: @database, properties: properties)
  end

  def sort_value_for_row(row, property)
    raw_value = cell_value_for(row, property)
    cast_sort_value_for_property(property, raw_value)
  end

  def board_group_value_for(row)
    raw_value = cell_value_for(row, @board_group_property).to_s.strip
    return nil if raw_value.blank?

    task_status_property?(@board_group_property) ? normalize_task_status_value(raw_value) : raw_value
  end

  def board_group_label_for(value)
    return value unless task_status_property?(@board_group_property)

    value.to_s.split.map(&:capitalize).join(" ")
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
    when "number", "progress"
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
    case @filter_operator
    when "neq"
      row_value != normalized_filter
    when "before"
      return false unless @filter_property.numeric_like? || @filter_property.date?
      return false if row_value.nil?

      row_value < normalized_filter
    when "after"
      return false unless @filter_property.numeric_like? || @filter_property.date?
      return false if row_value.nil?

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

  def unlocking_database_request?
    return false unless params.key?(:database)
    return false unless params[:database].respond_to?(:key?) && params[:database].key?(:locked)

    ActiveModel::Type::Boolean.new.cast(params.dig(:database, :locked)) == false
  end

  def database_redirect_path
    split_page_id = @clear_split_page ? nil : (@redirect_split_page_id || params[:split_page_id].presence)
    split_source = @clear_split_page ? nil : (@redirect_split_source || params[:split_source].presence)
    split_row_id = @clear_split_page ? nil : params[:split_row_id].presence
    split_panel = @redirect_split_panel || params[:split_panel].presence

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
      options_menu: params[:options_menu].presence,
      split_panel: split_panel,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id,
      task_row_id: params[:task_row_id].presence,
      kalendarium_window_start: params[:kalendarium_window_start].presence
    )
  end

  def resolve_split_page
    split_page_id = params[:split_page_id].presence
    return nil if split_page_id.blank?

    policy_scope(Page).for_workspace(@workspace).active.find_by(id: split_page_id)
  end

  def resolve_page_tabs
    PageTabs::Resolver.new(
      workspace: @workspace,
      page_scope: policy_scope(Page),
      database_scope: policy_scope(Database),
      group_page: @database.linked_page&.parent_page || @database.linked_page,
      current_database: @database
    ).call
  end

  def load_cells_for_rows_and_properties(property_ids:)
    row_ids = @rows.map(&:id)
    return [] if row_ids.empty? || property_ids.empty?

    DbCell
      .where(workspace_id: @workspace.id)
      .where(db_row_id: row_ids, db_property_id: property_ids)
      .to_a
  end

  def load_chart_export_cells(rows:, properties:)
    row_ids = Array(rows).map(&:id)
    property_ids = Array(properties).map(&:id)
    return {} if row_ids.empty? || property_ids.empty?

    DbCell
      .where(workspace_id: @workspace.id)
      .where(db_row_id: row_ids, db_property_id: property_ids)
      .to_a
      .index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
  end

  def prepare_gantt_export_context!
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @view_config = @current_view&.config_json.to_h || {}
    resolve_filter_and_sort_settings!

    @rows = Databases::RowWindowQueryService.new(
      scope: policy_scope(DbRow).for_database(@database).active,
      sort_property: @sort_property,
      sort_by_title: @sort_by_name,
      sort_direction: @sort_direction,
      sort_mode: @sort_mode,
      filter_property: @filter_property,
      filter_value: @filter_value,
      filter_operator: @filter_operator,
      view_type: "gantt",
      page: 1
    ).call.rows

    @visible_property_ids = resolve_visible_property_ids
    @visible_db_properties = if @visible_property_ids.present?
      @db_properties.select { |property| @visible_property_ids.include?(property.id.to_s) }
    else
      @db_properties
    end
    @cells_by_key = load_chart_export_cells(rows: @rows, properties: @db_properties)
    @gantt_split = Databases::GanttChartDataBuilder.new(
      rows: @rows,
      db_properties: @db_properties,
      cells_by_key: @cells_by_key,
      view_config: @view_config
    ).call
  end

  def prepare_graph_export_context!
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @view_config = @current_view&.config_json.to_h || {}
    resolve_filter_and_sort_settings!

    @rows = Databases::RowWindowQueryService.new(
      scope: policy_scope(DbRow).for_database(@database).active,
      sort_property: @sort_property,
      sort_by_title: @sort_by_name,
      sort_direction: @sort_direction,
      sort_mode: @sort_mode,
      filter_property: @filter_property,
      filter_value: @filter_value,
      filter_operator: @filter_operator,
      view_type: "graph",
      page: 1
    ).call.rows

    @graph_split = Databases::GraphChartDataBuilder.new(
      rows: @rows,
      db_properties: @visible_db_properties,
      cells_by_key: load_chart_export_cells(rows: @rows, properties: @visible_db_properties),
      view_config: @view_config
    ).call
  end

  def required_property_ids_for_cell_load
    required_ids = []
    required_ids.concat(@db_properties.map(&:id)) if @view_type == "board"
    required_ids.concat(@db_properties.map(&:id)) if @gantt_split_active
    required_ids.concat(Array(@visible_db_properties).map(&:id))
    required_ids << @sort_property&.id
    required_ids << @filter_property&.id
    required_ids << @conditional_color_property&.id
    required_ids << @board_group_property&.id if @view_type == "board"
    required_ids << @calendar_date_property&.id if @view_type == "calendar"
    required_ids.compact.uniq
  end

  def resolve_row_query
    Databases::RowWindowQueryService.new(
      scope: policy_scope(DbRow).for_database(@database).active,
      sort_property: @sort_property,
      sort_by_title: @sort_by_name,
      sort_direction: @sort_direction,
      sort_mode: @sort_mode,
      filter_property: @filter_property,
      filter_value: @filter_value,
      filter_operator: @filter_operator,
      view_type: @view_type,
      page: rows_page_param
    ).call
  end

  def rows_page_param
    value = params[:rows_page].to_i
    value.positive? ? value : 1
  end

  def schedule_missing_cells_backfill(property_ids:, loaded_cell_count:)
    row_ids = @rows.map(&:id)
    property_ids = Array(property_ids).compact
    return if row_ids.empty? || property_ids.empty?

    expected_count = row_ids.length * property_ids.length
    return if expected_count <= loaded_cell_count
    return if expected_count > 5_000

    DbCells::BackfillWindowJob.perform_later(@database.id, row_ids, property_ids)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    DbCells::BackfillService.call(
      database: @database,
      workspace: @workspace,
      row_ids: row_ids,
      property_ids: property_ids
    )
  end

  def database_panel_view_params
    {
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
      options_menu: params[:options_menu].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence,
      task_row_id: params[:task_row_id].presence,
      kalendarium_window_start: params[:kalendarium_window_start].presence
    }.compact
  end

  def database_panel_view_link
    database_url(
      database_panel_view_params.except(
        :view_settings,
        :actions_menu,
        :options_menu,
        :split_panel,
        :split_page_id,
        :split_source,
        :split_row_id,
        :task_row_id
      )
    )
  end

  def database_row_menu_params
    database_panel_view_params.except(
      :workspace_slug,
      :id,
      :view_settings,
      :view_settings_section,
      :actions_menu,
      :options_menu
    )
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

  def resolve_tasks_project_for_split
    existing_project =
      policy_scope(KalendariumProject).for_workspace(@workspace).find_by(slug: Kalendarium::TasksProjectEnsurer::PROJECT_SLUG) ||
      policy_scope(KalendariumProject).for_workspace(@workspace).where("LOWER(name) = ?", Kalendarium::TasksProjectEnsurer::PROJECT_NAME.downcase).order(:created_at).first
    return existing_project if existing_project.present?
    return nil unless can_manage_tasks_project?

    Kalendarium::TasksProjectEnsurer.new(workspace: @workspace, actor: current_user).call
  rescue ActiveRecord::RecordInvalid => error
    Rails.logger.warn("Could not prepare Tasks project for database split #{@database.id}: #{error.record.errors.full_messages.to_sentence}")
    nil
  end

  def resolve_kalendarium_task_row
    task_row_id = params[:task_row_id].to_s.presence
    return nil if task_row_id.blank?

    policy_scope(DbRow).for_database(@database).active.find_by(id: task_row_id)
  end

  def resolve_kalendarium_split_window_start
    requested_start = parse_kalendarium_window_start_param
    return requested_start if requested_start.present?

    today = Time.current.in_time_zone(current_user.time_zone).to_date
    return today if @kalendarium_task_row.blank? || @kalendarium_split_project.blank?

    candidate_result = Kalendarium::TaskSchedulingService.new(
      workspace: @workspace,
      row: @kalendarium_task_row,
      actor: current_user,
      tasks_project: @kalendarium_split_project,
      busy_calendar_ids: split_scheduling_calendar_ids,
      visible_project_ids: [ @kalendarium_split_project.id ]
    ).candidate_slots(limit: 1)
    return today unless candidate_result.success?

    first_slot = candidate_result.slots.first
    return today if first_slot.blank?

    first_slot_date = first_slot.starts_at.in_time_zone(current_user.time_zone).to_date
    return today if first_slot_date <= today + 6.days

    first_slot_date
  rescue StandardError => error
    Rails.logger.warn("Could not resolve split window start for database #{@database.id}: #{error.message}")
    today
  end

  def parse_kalendarium_window_start_param
    raw = params[:kalendarium_window_start].to_s.presence
    return nil if raw.blank?

    Date.iso8601(raw)
  rescue ArgumentError
    nil
  end

  def can_manage_tasks_project?
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

  def can_comment_on_database?
    database_comment_probe = Comment.new(commentable: @database, workspace: @workspace, author: current_user, body: "draft")
    policy(database_comment_probe).create?
  end

  def split_scheduling_calendar_ids
    selected_provider_calendar_ids_for_workspace + [ @kalendarium_split_project.kalendarium_calendar_id.to_s ]
  end

  def prepare_database_comments_panel!
    @can_comment_on_database = can_comment_on_database?
    @new_database_comment = Comment.new
    @database_comments = policy_scope(Comment)
                           .for_workspace(@workspace)
                           .where(commentable: @database)
                           .includes(:author, :resolved_by)
                           .order(created_at: :desc)
                           .to_a
  end

  def prepare_database_options_panel!
    can_manage_permissions = policy(@database).permissions?
    @can_move_database = policy(@database).move_workspace?
    @memberships =
      if can_manage_permissions
        policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
      else
        []
      end
    @move_workspace_options = @can_move_database ? move_workspace_options_for_database : []
    @archived_rows = policy_scope(DbRow).for_database(@database).where.not(archived_at: nil).ordered.to_a
    @database_share_links =
      if can_manage_permissions
        policy_scope(DatabaseShareLink).for_database(@database).recent_first.to_a
      else
        []
      end
    @shared_user_ids = can_manage_permissions ? @database.database_shares.pluck(:user_id) : []
  end

  def move_target_workspace!
    workspace_id = params.require(:target_workspace_id)
    policy_scope(Workspace).where.not(id: @workspace.id).find(workspace_id)
  end

  def move_workspace_options_for_database
    policy_scope(Workspace)
      .where.not(id: @workspace.id)
      .order(:name)
      .select do |candidate_workspace|
        probe_record = Database.new(workspace: candidate_workspace, name: @database.name)
        policy(probe_record).create?
      end
  end

  def prepare_database_actions_panel!
    prepare_database_view_context!
    row_query = resolve_row_query
    @rows = row_query.rows
    visible_property_ids = Array(@visible_db_properties).map(&:id)
    @cells = load_cells_for_rows_and_properties(property_ids: visible_property_ids)
    @cells_by_key = @cells.index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }
    @database_plain_text = build_database_plain_text
    @recent_database_audit_events = policy_scope(AuditEvent)
                                      .where(workspace_id: @workspace.id, auditable: @database)
                                      .recent_first
                                      .limit(10)
                                      .to_a
    @database_versions = @database.versions.reorder(created_at: :desc).limit(10).to_a
    @new_database_view = DatabaseView.new
  end

  def prepare_database_view_settings_panel!
    prepare_database_view_context!
  end

  def prepare_database_row_menu_panel!
    @row = policy_scope(DbRow).for_database(@database).active.includes(:linked_page).find(params[:row_id])
    authorize @row, :update?
  end

  def prepare_database_column_menu_panel!
    @db_property = policy_scope(DbProperty).for_database(@database).find(params[:property_id])
    authorize @db_property, :update?
  end

  def prepare_database_view_context!
    ensure_tab_shell_page!
    ensure_default_view!
    @db_properties = policy_scope(DbProperty).for_database(@database).ordered.to_a
    @database_views = policy_scope(DatabaseView).for_database(@database).ordered.to_a
    @current_view = resolve_current_view
    @view_type = @current_view&.view_type || "table"
    @view_config = @current_view&.config_json.to_h || {}
    resolve_filter_and_sort_settings!
  end

  def prepare_stats_template_data!
    @stats_date = Databases::StatsTemplateService.selected_date(params[:stats_date], today: Time.zone.today)
    @stats_mode = params[:stats_mode].to_s == "setup" ? "setup" : "report"
    @stats_frequency_options = Databases::StatsTemplateService::FREQUENCIES.map { |value, label| [ label, value ] }

    if @stats_mode == "setup"
      @stats_definitions = Databases::StatsTemplateService.setup_definitions(@database)
    else
      @stats_report_rows = Databases::StatsTemplateService.report_rows(database: @database, date: @stats_date)
    end
  end

  def stats_setup_params
    raw = params[:stats].respond_to?(:to_unsafe_h) ? params[:stats].to_unsafe_h : {}
    {
      "definitions" => raw.fetch("definitions", {}),
      "new_definition" => raw.fetch("new_definition", {})
    }
  end

  def stats_entries_params
    raw = params[:stats].respond_to?(:to_unsafe_h) ? params[:stats].to_unsafe_h : {}
    {
      "entries" => raw.fetch("entries", {})
    }
  end

  def normalize_template(raw_template)
    template = raw_template.to_s
    return "tasks" if template == "tasks"
    return "stats" if template == "stats"

    "blank"
  end

  def apply_template_default_name!(template)
    return unless @database.name.to_s.strip.blank?

    @database.name =
      case template
      when "tasks" then "Tasks grid"
      when "stats" then "Stats grid"
      else "Untitled grid"
      end
  end

  def apply_template!(template, table_view:)
    case template
    when "tasks"
      build_tasks_template!(table_view:)
      @database.update!(database_template: nil, applied_template_name: "Tasks")
    when "stats"
      Databases::StatsTemplateService.apply!(database: @database, table_view:)
    end
  end

  def build_tasks_template!(table_view:)
    task_properties = TASK_TEMPLATE_PROPERTIES.map do |name, property_type|
      find_or_create_task_template_property!(name:, property_type:)
    end

    seed_task_template_cells!(properties: task_properties)

    return if table_view.blank?

    config = table_view.config_json.to_h
    config["visible_property_ids"] = task_properties.map { |property| property.id.to_s }
    table_view.update!(config_json: config)
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

  def resolve_or_create_table_view!
    existing_table = @database.database_views.ordered.find { |view| view.view_type == "table" }
    return existing_table if existing_table.present?

    @database.database_views.create!(
      workspace: @workspace,
      created_by: current_user,
      name: next_available_view_name("Table"),
      view_type: :table,
      default: @database.database_views.none?
    )
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

  def tasks_template_convertible?(properties: nil)
    grouped_properties = Array(properties || @database.db_properties.ordered.to_a).group_by do |property|
      normalize_task_template_property_name(property.name)
    end

    grouped_properties.all? do |property_name, matching_properties|
      expected_type = TASK_TEMPLATE_PROPERTY_TYPES[property_name]
      expected_type.present? &&
        matching_properties.one? &&
        matching_properties.first.property_type == expected_type
    end
  end

  def stats_template_convertible?(properties: nil)
    return true if Databases::StatsTemplateService.stats_database?(@database)

    Array(properties || @database.db_properties.ordered.to_a).empty?
  end

  def tasks_template_ready?(properties: nil)
    normalized_types = Array(properties || @database.db_properties.ordered.to_a).each_with_object({}) do |property, index|
      index[normalize_task_template_property_name(property.name)] = property.property_type
    end

    TASK_TEMPLATE_PROPERTY_TYPES.all? do |property_name, property_type|
      normalized_types[property_name] == property_type
    end
  end

  def find_or_create_task_template_property!(name:, property_type:)
    existing_property = @database.db_properties.ordered.find do |property|
      normalize_task_template_property_name(property.name) == normalize_task_template_property_name(name)
    end
    return existing_property if existing_property.present? && existing_property.property_type == property_type

    if existing_property.present?
      existing_property.errors.add(:property_type, "must be #{property_type} to use the Tasks template")
      raise ActiveRecord::RecordInvalid, existing_property
    end

    @database.db_properties.create!(
      workspace: @workspace,
      name: name,
      property_type: property_type
    )
  end

  def seed_task_template_cells!(properties:)
    rows = @database.db_rows.order(:created_at).to_a
    return if rows.empty? || properties.empty?

    property_ids = properties.map(&:id)
    existing_cells = policy_scope(DbCell)
                       .for_database(@database)
                       .where(db_row_id: rows.map(&:id), db_property_id: property_ids)
                       .index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }

    rows.each do |row|
      properties.each do |property|
        default_value = task_template_default_value_for(row:, property:)
        existing_cell = existing_cells[[ row.id, property.id ]]

        if existing_cell.present?
          next if default_value.blank?
          next unless existing_cell.value_text.to_s.blank?

          existing_cell.update!(value_text: default_value)
          next
        end

        DbCell.create!(
          workspace: @workspace,
          db_row: row,
          db_property: property,
          value_text: default_value
        )
      end
    end
  end

  def task_template_default_value_for(row:, property:)
    case normalize_task_template_property_name(property.name)
    when "status"
      "not started"
    when "date created"
      row.created_at.to_date.iso8601
    else
      ""
    end
  end

  def normalize_task_template_property_name(name)
    name.to_s.strip.downcase
  end

  def current_database_template_label
    @database.applied_template_name.presence ||
      @database.database_template&.name.presence ||
      (@tasks_template_ready ? "Tasks" : "Grid")
  end

  def resolve_template_source_view
    requested_view_id = params[:view_id].presence
    return @current_view if requested_view_id.blank? && defined?(@current_view) && @current_view.present?

    policy_scope(DatabaseView).for_database(@database).find_by(id: requested_view_id) ||
      @current_view ||
      @database.database_views.ordered.first
  end

  def database_template_name
    params.dig(:database_template, :name).to_s
  end
end
