class DbRowsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :ensure_database_unlocked!
  before_action :set_db_row, only: %i[update destroy move duplicate]

  def create
    @db_row = @database.db_rows.new(db_row_params)
    @db_row.title = "Untitled row" if @db_row.title.blank?
    authorize @db_row
    apply_linked_page_update!

    if @db_row.errors.any?
      redirect_to database_redirect_location, alert: @db_row.errors.full_messages.to_sentence
      return
    end

    if @db_row.save
      insert_row_after_reference!(@db_row, params[:insert_after_id]) if params[:insert_after_id].present?
      seed_cells_for_row(@db_row)
      assign_date_value_to_row(@db_row)
      clear_row_sorting_preferences! if params[:insert_after_id].present?
      if @redirect_split_source == "row" && @redirect_split_page_id.present?
        @redirect_split_row_id ||= @db_row.id
      end
      redirect_to database_redirect_location, notice: "Row created."
    else
      redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id), alert: @db_row.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @db_row, :update?
    @db_row.assign_attributes(db_row_params)
    apply_linked_page_update!
    apply_row_style_update!

    if @db_row.errors.any?
      redirect_to database_redirect_location(anchor: "row_#{@db_row.id}"), alert: @db_row.errors.full_messages.to_sentence
      return
    end

    @db_row.title = "Untitled row" if @db_row.title.blank?

    if @db_row.save
      redirect_to database_redirect_location(anchor: "row_#{@db_row.id}"), notice: "Row updated."
    else
      redirect_to database_redirect_location(anchor: "row_#{@db_row.id}"), alert: @db_row.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @db_row, :destroy?
    @db_row.update!(archived_at: Time.current)
    redirect_to database_redirect_location, notice: "Row archived."
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

  def set_db_row
    @db_row = policy_scope(DbRow).for_database(@database).find(params[:id])
  end

  def seed_cells_for_row(row)
    policy_scope(DbProperty).for_database(@database).ordered.each do |db_property|
      row.db_cells.find_or_create_by!(db_property:, workspace: @workspace) do |cell|
        cell.value_text = ""
      end
    end
  end

  def assign_date_value_to_row(row)
    date_property_id = params[:date_property_id].presence
    date_value = params[:date_value].presence
    return if date_property_id.blank? || date_value.blank?

    date_property = policy_scope(DbProperty).for_database(@database).find_by(id: date_property_id, property_type: :date)
    return if date_property.blank?

    row.db_cells.find_or_create_by!(db_property: date_property, workspace: @workspace) do |cell|
      cell.value_text = date_value
    end.tap do |cell|
      cell.update!(value_text: date_value)
    end
  end

  def database_redirect_location(anchor: nil)
    split_page_id = @clear_split_page ? nil : (@redirect_split_page_id || params[:split_page_id].presence)
    split_source = @clear_split_page ? nil : (@redirect_split_source || params[:split_source].presence)
    split_row_id = @clear_split_page ? nil : (@redirect_split_row_id || params[:split_row_id].presence)

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
      view_settings: params[:view_settings].presence,
      actions_menu: params[:actions_menu].presence,
      split_page_id: split_page_id,
      split_source: split_source,
      split_row_id: split_row_id
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
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence
    )
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

    DbRows::MoveService.call(
      row: row,
      database: @database,
      workspace: @workspace,
      property: nil,
      target_value: nil,
      target_index: reference_index + 1
    )
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

  def ensure_database_unlocked!
    return unless @database.locked?

    redirect_to database_redirect_location, alert: "Grid is locked. Unlock to make changes."
  end
end
