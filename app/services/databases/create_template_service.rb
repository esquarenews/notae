module Databases
  class CreateTemplateService
    NAME_SORT_SENTINEL = "__row_title__".freeze

    SINGLE_PROPERTY_CONFIG_KEYS = {
      "sort_property_id" => "sort_property_name",
      "filter_property_id" => "filter_property_name",
      "group_property_id" => "group_property_name",
      "date_property_id" => "date_property_name",
      "conditional_color_property_id" => "conditional_color_property_name"
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

    class << self
      def call(database:, current_view:, created_by:, name:)
        new(database:, current_view:, created_by:, name:).call
      end
    end

    def initialize(database:, current_view:, created_by:, name:)
      @database = database
      @current_view = current_view
      @created_by = created_by
      @name = name
    end

    def call
      DatabaseTemplate.create!(
        workspace: database.workspace,
        database: database,
        created_by: created_by,
        name: resolved_name,
        snapshot_json: snapshot_json
      )
    end

    private

    attr_reader :database, :current_view, :created_by, :name

    def resolved_name
      name.to_s.strip.presence || database.name
    end

    def ordered_properties
      @ordered_properties ||= database.db_properties.order(:position, :created_at).to_a
    end

    def property_name_by_id
      @property_name_by_id ||= ordered_properties.each_with_object({}) do |property, index|
        index[property.id.to_s] = property.name
      end
    end

    def snapshot_json
      {
        "database_name" => database.name,
        "properties" => ordered_properties.map do |property|
          {
            "name" => property.name,
            "property_type" => property.property_type,
            "position" => property.position
          }
        end,
        "view" => view_snapshot
      }
    end

    def view_snapshot
      source_view = current_view || database.database_views.ordered.first
      return {} if source_view.blank?

      {
        "name" => source_view.name,
        "view_type" => source_view.view_type,
        "config_json" => serialize_view_config(source_view.config_json.to_h)
      }
    end

    def serialize_view_config(raw_config)
      config = raw_config.to_h.deep_dup
      snapshot = {}

      SINGLE_PROPERTY_CONFIG_KEYS.each do |config_key, snapshot_key|
        if config_key == "sort_property_id" && config[config_key].to_s == DatabaseView::NAME_SORT_KEY
          snapshot[snapshot_key] = NAME_SORT_SENTINEL
          next
        end

        property_name = property_name_by_id[config[config_key].to_s]
        snapshot[snapshot_key] = property_name if property_name.present?
      end

      PASSTHROUGH_CONFIG_KEYS.each do |config_key|
        snapshot[config_key] = config[config_key] if config.key?(config_key)
      end

      visible_property_names = Array(config["visible_property_ids"]).map { |property_id| property_name_by_id[property_id.to_s] }.compact
      snapshot["visible_property_names"] = visible_property_names if visible_property_names.any?

      column_widths = serialize_column_widths(config["column_widths"])
      snapshot["column_widths"] = column_widths if column_widths.present?

      snapshot.compact
    end

    def serialize_column_widths(raw_widths)
      return if !raw_widths.respond_to?(:to_h)

      raw_widths.to_h.each_with_object({ "properties" => {} }) do |(key, value), widths|
        column_key = key.to_s
        if column_key == "name"
          widths["name"] = value
          next
        end

        property_id = column_key.delete_prefix("property_")
        next unless column_key.start_with?("property_")

        property_name = property_name_by_id[property_id.to_s]
        next if property_name.blank?

        widths["properties"][property_name] = value
      end.tap do |widths|
        widths.delete("properties") if widths["properties"].blank?
      end.presence
    end
  end
end
