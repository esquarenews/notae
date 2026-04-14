module Databases
  class ApplyTemplateService
    Result = Struct.new(:view, keyword_init: true)

    SINGLE_PROPERTY_CONFIG_KEYS = {
      "sort_property_name" => "sort_property_id",
      "filter_property_name" => "filter_property_id",
      "group_property_name" => "group_property_id",
      "date_property_name" => "date_property_id",
      "conditional_color_property_name" => "conditional_color_property_id"
    }.freeze
    PASSTHROUGH_CONFIG_KEYS = %w[
      sort_direction
      sort_mode
      filter_value
      filter_operator
      conditional_color_mode
      gantt_status_colors
      graph_type
      graph_show_values
      graph_split_series
    ].freeze
    PROPERTY_POSITION_STEP = 1024

    class << self
      def call(database:, template:, created_by:)
        new(database:, template:, created_by:).call
      end
    end

    def initialize(database:, template:, created_by:)
      @database = database
      @template = template
      @created_by = created_by
    end

    def call
      ActiveRecord::Base.transaction do
        property_map = ensure_template_properties!
        target_view = ensure_target_view!
        target_view.update!(config_json: build_view_config(property_map))
        target_view.set_as_default!
        database.update!(
          database_template: template,
          applied_template_name: template.name
        )
        Result.new(view: target_view)
      end
    end

    private

    attr_reader :database, :template, :created_by

    def template_snapshot
      @template_snapshot ||= template.snapshot_json.to_h
    end

    def template_properties
      Array(template_snapshot["properties"]).filter_map do |property_snapshot|
        next unless property_snapshot.is_a?(Hash)

        name = property_snapshot["name"].to_s.strip
        property_type = property_snapshot["property_type"].to_s.strip
        next if name.blank? || property_type.blank?

        {
          "name" => name,
          "property_type" => property_type
        }
      end
    end

    def template_view_snapshot
      template_snapshot["view"].to_h
    end

    def ensure_template_properties!
      normalized_property_map = {}

      template_properties.each do |property_snapshot|
        property = find_or_create_property!(
          name: property_snapshot.fetch("name"),
          property_type: property_snapshot.fetch("property_type")
        )
        normalized_property_map[normalize_property_name(property.name)] = property
      end

      reposition_properties!(normalized_property_map.values)
      normalized_property_map
    end

    def find_or_create_property!(name:, property_type:)
      existing_property = database.db_properties.ordered.find do |property|
        normalize_property_name(property.name) == normalize_property_name(name)
      end
      return existing_property if existing_property.present? && existing_property.property_type == property_type

      if existing_property.present?
        existing_property.errors.add(:property_type, "must be #{property_type} to use the #{template.name} template")
        raise ActiveRecord::RecordInvalid, existing_property
      end

      database.db_properties.create!(
        workspace: database.workspace,
        name: name,
        property_type: property_type
      )
    end

    def reposition_properties!(template_property_records)
      template_property_records.each_with_index do |property, index|
        desired_position = (index + 1) * PROPERTY_POSITION_STEP
        property.update!(position: desired_position) if property.position != desired_position
      end

      remaining_properties = database.db_properties.ordered.reject { |property| template_property_records.include?(property) }
      remaining_properties.each_with_index do |property, index|
        desired_position = (template_property_records.length + index + 1) * PROPERTY_POSITION_STEP
        property.update!(position: desired_position) if property.position != desired_position
      end
    end

    def ensure_target_view!
      requested_view_type = normalize_view_type(template_view_snapshot["view_type"])
      existing_view = database.database_views.ordered.find { |view| view.view_type == requested_view_type }
      return existing_view if existing_view.present?

      database.database_views.create!(
        workspace: database.workspace,
        created_by: created_by,
        name: next_available_view_name(template_view_snapshot["name"].presence || requested_view_type.titleize),
        view_type: requested_view_type,
        default: database.database_views.none?
      )
    end

    def next_available_view_name(base_name)
      existing_names = database.database_views.pluck(:name).map { |candidate| candidate.to_s.downcase }
      return base_name unless existing_names.include?(base_name.downcase)

      suffix = 2
      loop do
        candidate = "#{base_name} #{suffix}"
        return candidate unless existing_names.include?(candidate.downcase)

        suffix += 1
      end
    end

    def normalize_view_type(raw_view_type)
      candidate = raw_view_type.to_s
      return candidate if DatabaseView.view_types.key?(candidate)

      "table"
    end

    def build_view_config(property_map)
      snapshot_config = template_view_snapshot["config_json"].to_h
      config = {}

      SINGLE_PROPERTY_CONFIG_KEYS.each do |snapshot_key, config_key|
        if config_key == "sort_property_id" && snapshot_config[snapshot_key].to_s == Databases::CreateTemplateService::NAME_SORT_SENTINEL
          config[config_key] = DatabaseView::NAME_SORT_KEY
          next
        end

        property = property_map[normalize_property_name(snapshot_config[snapshot_key])]
        config[config_key] = property.id if property.present?
      end

      PASSTHROUGH_CONFIG_KEYS.each do |config_key|
        config[config_key] = snapshot_config[config_key] if snapshot_config.key?(config_key)
      end

      visible_property_ids = Array(snapshot_config["visible_property_names"]).filter_map do |property_name|
        property_map[normalize_property_name(property_name)]&.id
      end
      config["visible_property_ids"] = visible_property_ids if visible_property_ids.any?

      column_widths = build_column_widths(snapshot_config["column_widths"], property_map)
      config["column_widths"] = column_widths if column_widths.present?

      config.compact
    end

    def build_column_widths(raw_widths, property_map)
      return if !raw_widths.respond_to?(:to_h)

      raw_widths.to_h.each_with_object({}) do |(key, value), widths|
        column_key = key.to_s
        if column_key == "name"
          widths["name"] = value
          next
        end

        next unless column_key == "properties"

        value.to_h.each do |property_name, width_value|
          property = property_map[normalize_property_name(property_name)]
          next if property.blank?

          widths["property_#{property.id}"] = width_value
        end
      end.presence
    end

    def normalize_property_name(name)
      name.to_s.strip.downcase
    end
  end
end
