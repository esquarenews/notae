class DatabaseViewsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :ensure_database_unlocked!, only: %i[create update set_default]
  before_action :set_database_view, only: %i[update set_default]

  def create
    @database_view = @database.database_views.new(database_view_params)
    @database_view.created_by = current_user
    authorize @database_view

    if @database_view.save
      @database_view.set_as_default! if @database_view.default?
      redirect_to database_path(database_view_redirect_params(@database_view)), notice: "View saved."
    else
      redirect_to database_path(database_view_redirect_params(@database_view)), alert: @database_view.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @database_view

    if @database_view.update(database_view_params)
      @database_view.set_as_default! if @database_view.default?
      respond_to do |format|
        format.html do
          redirect_to database_path(database_view_redirect_params(@database_view)), notice: "View updated."
        end
        format.json do
          render json: {
            id: @database_view.id,
            config_json: @database_view.config_json.to_h
          }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_to database_path(workspace_slug: @workspace.slug, id: @database.id, view_id: @database_view.id), alert: @database_view.errors.full_messages.to_sentence
        end
        format.json { render json: { errors: @database_view.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def set_default
    authorize @database_view, :set_default?
    @database_view.set_as_default!
    redirect_to database_path(database_view_redirect_params(@database_view)), notice: "Default view set."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).active.find(params[:database_id])
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
      :filter_operator,
      :group_property_id,
      :date_property_id,
      :conditional_color_mode,
      :conditional_color_property_id,
      visible_property_ids: [],
      column_widths: {},
      gantt_status_colors: {}
    )

    config = @database_view&.config_json.to_h.deep_dup

    apply_config_value!(config, "sort_property_id", permitted, :sort_property_id) { |value| value.presence }
    apply_config_value!(config, "sort_direction", permitted, :sort_direction) { |value| normalize_sort_direction(value) }
    apply_config_value!(config, "filter_property_id", permitted, :filter_property_id) { |value| value.presence }
    apply_config_value!(config, "filter_value", permitted, :filter_value) { |value| value.presence }
    apply_config_value!(config, "filter_operator", permitted, :filter_operator) { |value| normalize_filter_operator(value) }
    apply_config_value!(config, "group_property_id", permitted, :group_property_id) { |value| value.presence }
    apply_config_value!(config, "date_property_id", permitted, :date_property_id) { |value| value.presence }
    apply_config_value!(config, "conditional_color_mode", permitted, :conditional_color_mode) do |value|
      normalize_conditional_color_mode(value)
    end
    apply_config_value!(config, "conditional_color_property_id", permitted, :conditional_color_property_id) do |value|
      value.presence
    end

    if permitted.key?(:visible_property_ids)
      visible_ids = Array(permitted.delete(:visible_property_ids)).map(&:to_s).reject(&:blank?).uniq
      if visible_ids.empty?
        config.delete("visible_property_ids")
      else
        config["visible_property_ids"] = visible_ids
      end
    end

    if permitted.key?(:column_widths)
      column_widths = normalize_column_widths(permitted.delete(:column_widths))
      if column_widths.empty?
        config.delete("column_widths")
      else
        config["column_widths"] = column_widths
      end
    end

    if permitted.key?(:gantt_status_colors)
      gantt_status_colors = normalize_gantt_status_colors(permitted.delete(:gantt_status_colors))
      existing_colors = config["gantt_status_colors"]
      merged_colors = (existing_colors.respond_to?(:to_h) ? existing_colors.to_h : {}).merge(gantt_status_colors)
      merged_colors.compact_blank!

      if merged_colors.empty?
        config.delete("gantt_status_colors")
      else
        config["gantt_status_colors"] = merged_colors
      end
    end

    permitted[:config_json] = config.compact
    permitted
  end

  def normalize_sort_direction(value)
    direction = value.to_s
    return direction if %w[asc desc].include?(direction)

    nil
  end

  def ensure_database_unlocked!
    return unless @database.locked?

    fallback_view = policy_scope(DatabaseView).for_database(@database).ordered.first || DatabaseView.new(id: params[:id], database: @database)
    redirect_to database_path(database_view_redirect_params(fallback_view)), alert: "Grid is locked. Unlock to make changes."
  end

  def normalize_filter_operator(value)
    operator = value.to_s
    return operator if %w[eq neq before after].include?(operator)

    nil
  end

  def normalize_conditional_color_mode(value)
    mode = value.to_s
    return mode if %w[overdue].include?(mode)

    nil
  end

  def apply_config_value!(config, config_key, params_hash, params_key)
    return unless params_hash.key?(params_key)

    raw_value = params_hash.delete(params_key)
    normalized_value = block_given? ? yield(raw_value) : raw_value

    if normalized_value.nil?
      config.delete(config_key)
    else
      config[config_key] = normalized_value
    end
  end

  def normalize_column_widths(raw_widths)
    return {} unless raw_widths.respond_to?(:to_h)

    allowed_property_ids = policy_scope(DbProperty).for_database(@database).pluck(:id).map(&:to_s)
    raw_widths.to_h.each_with_object({}) do |(key, value), widths|
      column_key = key.to_s
      minimum = minimum_width_for_column(column_key, allowed_property_ids)
      next if minimum.nil?

      width = parse_column_width(value)
      next if width.nil?

      widths[column_key] = width.clamp(minimum, 960)
    end
  end

  def normalize_gantt_status_colors(raw_colors)
    return {} unless raw_colors.respond_to?(:to_h)

    raw_colors.to_h.each_with_object({}) do |(key, value), colors|
      normalized_key = key.to_s
      normalized_value = value.to_s.strip.upcase
      next if normalized_key.blank?
      next unless normalized_value.match?(/\A#(?:[0-9A-F]{3}|[0-9A-F]{6})\z/)

      colors[normalized_key] = normalized_value
    end
  end

  def minimum_width_for_column(column_key, allowed_property_ids)
    return 180 if column_key == "name"

    property_id = column_key.delete_prefix("property_")
    return nil unless property_id.present? && column_key.start_with?("property_")
    return nil unless allowed_property_ids.include?(property_id)

    120
  end

  def parse_column_width(value)
    Integer(value.to_s, 10)
  rescue ArgumentError, TypeError
    nil
  end

  def database_view_redirect_params(database_view)
    {
      workspace_slug: @workspace.slug,
      id: @database.id,
      view_id: database_view.id,
      month: params[:month].presence,
      filter_property_id: params[:filter_property_id].presence,
      filter_value: params[:filter_value].presence,
      filter_operator: params[:filter_operator].presence,
      rows_page: params[:rows_page].presence,
      split_panel: params[:split_panel].presence,
      split_page_id: params[:split_page_id].presence,
      split_source: params[:split_source].presence,
      split_row_id: params[:split_row_id].presence,
      task_row_id: params[:task_row_id].presence,
      view_settings: params[:view_settings].presence,
      view_settings_section: params[:view_settings_section].presence,
      actions_menu: params[:actions_menu].presence
    }.compact
  end
end
