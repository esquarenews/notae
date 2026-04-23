module DatabaseTablePresentation
  extend ActiveSupport::Concern

  TASK_STATUS_OPTIONS = [ "not started", "started", "overdue", "hold", "done" ].freeze
  TASK_STATUS_NORMALIZATION_MAP = {
    "planning" => "not started",
    "on hold" => "hold",
    "complete" => "done",
    "completed" => "done",
    "in progress" => "started"
  }.freeze
  TASK_STATUS_CLASS_MAP = {
    "not started" => "is-status-not-started",
    "started" => "is-status-started",
    "overdue" => "is-status-overdue",
    "hold" => "is-status-hold",
    "done" => "is-status-done"
  }.freeze

  included do
    helper_method :cell_value_for, :select_options_for, :conditional_color_class_for_row, :select_input_classes_for, :task_status_badge_classes_for, :column_style_classes_for, :name_column_style_classes_for
  end

  private

  def cell_value_for(row, property)
    return "" if row.blank? || property.blank?

    @cells_by_key[[ row.id, property.id ]]&.value_text.to_s
  end

  def select_options_for(property)
    return [] if property.blank?

    @select_options_by_property[property.id] || []
  end

  def build_select_options_lookup(database:, properties:)
    select_properties = Array(properties).select(&:select?)
    return {} if select_properties.empty?

    values_by_property = Hash.new { |hash, key| hash[key] = [] }
    DbCell
      .where(workspace_id: database.workspace_id)
      .where(db_property_id: select_properties.map(&:id))
      .where.not(value_text: [ nil, "" ])
      .distinct
      .order(:db_property_id, :value_text)
      .pluck(:db_property_id, :value_text)
      .each do |property_id, value_text|
        values_by_property[property_id] << value_text
      end

    select_properties.each_with_object({}) do |property, lookup|
      lookup[property.id] = select_options_with_fallback(property, values_by_property[property.id])
    end
  end

  def select_options_with_fallback(property, existing_values = [])
    values = []
    seen = {}

    if task_status_property?(property)
      TASK_STATUS_OPTIONS.each do |value|
        seen[value] = true
        values << value
      end
    end

    property.select_options_list.each do |value|
      normalized = task_status_property?(property) ? normalize_task_status_value(value) : value.to_s.strip
      next if normalized.blank? || seen.key?(normalized)

      seen[normalized] = true
      values << normalized
    end

    Array(existing_values).each do |value|
      normalized = task_status_property?(property) ? normalize_task_status_value(value) : value.to_s.strip
      next if normalized.blank? || seen.key?(normalized)

      seen[normalized] = true
      values << normalized
    end

    values
  end

  def select_input_classes_for(property, value)
    classes = [ "notae-db-cell-input" ]
    return classes.join(" ") unless task_status_property?(property)

    normalized_value = normalize_task_status_value(value)
    classes << "notae-db-cell-select-status"
    classes << TASK_STATUS_CLASS_MAP[normalized_value] if TASK_STATUS_CLASS_MAP.key?(normalized_value)
    classes.join(" ")
  end

  def task_status_badge_classes_for(property, value, base_class: "notae-db-status-badge")
    classes = [ base_class ]
    return classes.join(" ") unless task_status_property?(property)

    normalized_value = normalize_task_status_value(value)
    classes << "notae-db-cell-select-status"
    classes << TASK_STATUS_CLASS_MAP[normalized_value] if TASK_STATUS_CLASS_MAP.key?(normalized_value)
    classes.join(" ")
  end

  def conditional_color_class_for_row(row)
    return nil unless @conditional_color_mode == "overdue"
    return nil if @conditional_color_property.blank?

    due_date = parse_database_table_date_value(cell_value_for(row, @conditional_color_property))
    return nil unless due_date.is_a?(Date)
    return nil unless due_date < Date.current

    "is-overdue-highlight"
  end

  def column_style_classes_for(property)
    return "" if property.blank?

    classes = []
    classes << "is-column-bold" if property.column_bold?
    classes << "is-column-italic" if property.column_italic?
    color = property.column_text_color
    classes << "is-column-color-#{color}" unless color == "default"
    background_color = property.column_background_color
    classes << "is-column-bg-#{background_color}" unless background_color == "default"
    classes.join(" ")
  end

  def name_column_style_classes_for(database)
    return "" if database.blank?

    classes = []
    classes << "is-column-bold" if database.name_column_text_bold?
    classes << "is-column-italic" if database.name_column_text_italic?
    color = database.name_column_text_color
    classes << "is-column-color-#{color}" unless color == "default"
    background_color = database.name_column_background_color
    classes << "is-column-bg-#{background_color}" unless background_color == "default"
    classes.join(" ")
  end

  def task_status_property?(property)
    property.present? && property.select? && property.name.to_s.strip.casecmp("status").zero?
  end

  def normalize_task_status_value(value)
    normalized = value.to_s.strip.downcase
    TASK_STATUS_NORMALIZATION_MAP.fetch(normalized, normalized)
  end

  def parse_database_table_date_value(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
