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
    helper_method :cell_value_for, :select_options_for, :conditional_color_class_for_row, :select_input_classes_for, :task_status_badge_classes_for, :column_style_classes_for, :name_column_style_classes_for, :database_property_heading, :timesheet_clock_property?, :timesheet_total_property?, :timesheet_row_started_at, :timesheet_row_active?, :datetime_local_cell_value
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

  def database_property_heading(property)
    name = property&.name.to_s
    normalized = name.strip.downcase
    icon_class =
      case normalized
      when "date/time clock started"
        "is-start"
      when "date/time clock stopped"
        "is-stop"
      end

    return name if icon_class.blank?

    helpers.safe_join(
      [
        helpers.content_tag(:span, "⏱", class: "notae-db-grid-heading-icon notae-timesheet-clock-icon #{icon_class}", aria: { hidden: true }),
        helpers.content_tag(:span, name)
      ],
      " "
    )
  end

  def timesheet_clock_property?(property)
    property&.text? &&
      property.name.to_s.strip.downcase.in?([ "date/time clock started", "date/time clock stopped" ])
  end

  def timesheet_total_property?(property)
    property.present? && property.name.to_s.strip.downcase == "calculated total time"
  end

  def timesheet_row_started_at(row, properties, cells_by_key)
    started_property = Array(properties).find { |property| property.name.to_s.strip.downcase == "date/time clock started" }
    return "" if started_property.blank?

    cells_by_key[[ row.id, started_property.id ]]&.value_text.to_s
  end

  def timesheet_row_active?(row, properties, cells_by_key)
    started_at = timesheet_row_started_at(row, properties, cells_by_key)
    return false if started_at.blank?

    stopped_property = Array(properties).find { |property| property.name.to_s.strip.downcase == "date/time clock stopped" }
    stopped_at = stopped_property.present? ? cells_by_key[[ row.id, stopped_property.id ]]&.value_text.to_s : ""
    stopped_at.blank?
  end

  def datetime_local_cell_value(value)
    raw = value.to_s.strip
    return "" if raw.blank?

    parsed_time = Time.zone.parse(raw)
    return raw if parsed_time.blank?

    parsed_time.strftime("%Y-%m-%dT%H:%M:%S")
  rescue ArgumentError
    raw
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
