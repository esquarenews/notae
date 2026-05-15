module Databases
  class StatsTemplateService
    TEMPLATE_NAME = "Stats".freeze
    ROW_TYPE_KEY = "__notae_stats_row_type".freeze
    ROW_TYPE_DEFINITION = "definition".freeze
    ROW_TYPE_ENTRY = "entry".freeze
    DEFINITION_ID_KEY = "__notae_stats_definition_row_id".freeze
    FREQUENCY_KEY = "__notae_stats_frequency".freeze
    PERIOD_START_KEY = "__notae_stats_period_start".freeze
    PERIOD_END_KEY = "__notae_stats_period_end".freeze

    PROPERTY_DEFINITIONS = [
      [ "Frequency", "select" ],
      [ "Assigned person", "text" ],
      [ "Post", "text" ],
      [ "Period start", "date" ],
      [ "Period label", "text" ],
      [ "Value", "number" ]
    ].freeze

    FREQUENCIES = {
      "daily" => "Daily",
      "weekly_mon_sun" => "Weekly Mon-Sun",
      "weekly_thu_2pm" => "Weekly Thursday 2pm-Thursday 2pm",
      "monthly" => "Monthly",
      "quarterly" => "Quarterly"
    }.freeze

    ReportRow = Struct.new(:definition, :entry, :period, keyword_init: true)
    Period = Struct.new(:start_date, :end_date, :label, keyword_init: true)

    class << self
      def stats_database?(database)
        database.applied_template_name.to_s == TEMPLATE_NAME
      end

      def apply!(database:, table_view: nil)
        properties = PROPERTY_DEFINITIONS.map do |name, property_type|
          find_or_create_property!(database:, name:, property_type:)
        end

        database.update!(database_template: nil, applied_template_name: TEMPLATE_NAME)

        return if table_view.blank?

        config = table_view.config_json.to_h
        config["visible_property_ids"] = properties.map { |property| property.id.to_s }
        table_view.update!(config_json: config)
      end

      def selected_date(raw_date, today: Date.current)
        Date.iso8601(raw_date.to_s)
      rescue ArgumentError
        today
      end

      def setup_definitions(database)
        definition_rows(database, include_archived: false)
      end

      def report_rows(database:, date:)
        definitions = definition_rows(database, include_archived: true)
        entries = entry_rows(database)
        active_definition_ids = definition_rows(database, include_archived: false).map(&:id)

        definitions.filter_map do |definition|
          period = period_for(date:, frequency: frequency_for(definition))
          entry = matching_entry(entries:, definition:, period:)
          next if entry.blank? && active_definition_ids.exclude?(definition.id)

          ReportRow.new(definition:, entry:, period:)
        end
      end

      def save_setup!(database:, definition_params:, new_definition_params: {}, archive_definition_id: nil)
        properties = property_index(database)

        Array(definition_params).each do |id, attributes|
          row = database.db_rows.find_by(id:)
          next unless definition_row?(row)

          update_definition!(row:, properties:, attributes:)
        end

        create_definition!(database:, properties:, attributes: new_definition_params)

        archive_definition!(database:, id: archive_definition_id)
      end

      def save_entries!(database:, date:, entry_params:)
        properties = property_index(database)
        entries = entry_rows(database)

        Array(entry_params).each do |definition_id, attributes|
          definition = database.db_rows.find_by(id: definition_id)
          next unless definition_row?(definition)

          value = attributes.to_h["value"].to_s.strip
          period = period_for(date:, frequency: frequency_for(definition))
          entry = matching_entry(entries:, definition:, period:) ||
            database.db_rows.create!(
              database:,
              workspace: database.workspace,
              title: definition.title,
              data_json: entry_metadata(definition:, period:)
            )

          entry.update!(title: definition.title, data_json: entry.data_json.to_h.merge(entry_metadata(definition:, period:)))
          set_cell!(row: entry, property: properties.fetch("Period start"), value: period.start_date.iso8601)
          set_cell!(row: entry, property: properties.fetch("Period label"), value: period.label)
          set_cell!(row: entry, property: properties.fetch("Value"), value:)
        end
      end

      def frequency_for(definition)
        metadata = definition.data_json.to_h
        frequency = metadata[FREQUENCY_KEY].to_s
        return frequency if FREQUENCIES.key?(frequency)

        FREQUENCIES.key(metadata["Frequency"].to_s) || "weekly_mon_sun"
      end

      def cell_value(row, property_name)
        return "" if row.blank?

        row.data_json.to_h[property_name].to_s
      end

      def period_for(date:, frequency:)
        case frequency.to_s
        when "daily"
          Period.new(start_date: date, end_date: date, label: date.strftime("%d %b %Y"))
        when "weekly_thu_2pm"
          start_date = date - ((date.wday - 4) % 7)
          end_date = start_date + 7.days
          Period.new(start_date:, end_date:, label: "#{start_date.strftime('%d %b %Y')} 2pm - #{end_date.strftime('%d %b %Y')} 2pm")
        when "monthly"
          start_date = date.beginning_of_month
          end_date = date.end_of_month
          Period.new(start_date:, end_date:, label: date.strftime("%B %Y"))
        when "quarterly"
          quarter_month = (((date.month - 1) / 3) * 3) + 1
          start_date = Date.new(date.year, quarter_month, 1)
          end_date = (start_date + 3.months) - 1.day
          Period.new(start_date:, end_date:, label: "Q#{((date.month - 1) / 3) + 1} #{date.year}")
        else
          start_date = date.beginning_of_week(:monday)
          end_date = date.end_of_week(:monday)
          Period.new(start_date:, end_date:, label: "#{start_date.strftime('%d %b %Y')} - #{end_date.strftime('%d %b %Y')}")
        end
      end

      private

      def find_or_create_property!(database:, name:, property_type:)
        property = database.db_properties.ordered.find { |candidate| candidate.name.casecmp?(name) }
        if property.present?
          property.update!(property_type:) unless property.property_type == property_type
          property.update!(select_options_list: FREQUENCIES.values) if name == "Frequency"
          return property
        end

        database.db_properties.create!(
          workspace: database.workspace,
          name:,
          property_type:,
          select_options_list: (FREQUENCIES.values if name == "Frequency")
        )
      end

      def property_index(database)
        apply!(database:) unless PROPERTY_DEFINITIONS.all? { |name, _type| database.db_properties.exists?(name:) }
        database.db_properties.reload.index_by(&:name)
      end

      def definition_rows(database, include_archived:)
        scope = database.db_rows.where("data_json ->> ? = ?", ROW_TYPE_KEY, ROW_TYPE_DEFINITION).order(:position, :created_at)
        scope = scope.active unless include_archived
        scope.to_a
      end

      def entry_rows(database)
        database.db_rows.where("data_json ->> ? = ?", ROW_TYPE_KEY, ROW_TYPE_ENTRY).order(:position, :created_at).to_a
      end

      def definition_row?(row)
        row.present? && row.data_json.to_h[ROW_TYPE_KEY] == ROW_TYPE_DEFINITION
      end

      def matching_entry(entries:, definition:, period:)
        entries.find do |entry|
          metadata = entry.data_json.to_h
          metadata[DEFINITION_ID_KEY] == definition.id &&
            metadata[PERIOD_START_KEY] == period.start_date.iso8601
        end
      end

      def update_definition!(row:, properties:, attributes:)
        attrs = normalize_definition_attributes(attributes)
        return if attrs[:title].blank?

        row.update!(
          title: attrs[:title],
          data_json: row.data_json.to_h.merge(
            ROW_TYPE_KEY => ROW_TYPE_DEFINITION,
            FREQUENCY_KEY => attrs[:frequency],
            "Assigned person" => attrs[:assigned_person],
            "Post" => attrs[:post]
          )
        )
        set_cell!(row:, property: properties.fetch("Frequency"), value: FREQUENCIES.fetch(attrs[:frequency]))
        set_cell!(row:, property: properties.fetch("Assigned person"), value: attrs[:assigned_person])
        set_cell!(row:, property: properties.fetch("Post"), value: attrs[:post])
      end

      def create_definition!(database:, properties:, attributes:)
        attrs = normalize_definition_attributes(attributes)
        return if attrs[:title].blank?

        row = database.db_rows.create!(
          database:,
          workspace: database.workspace,
          title: attrs[:title],
          data_json: {
            ROW_TYPE_KEY => ROW_TYPE_DEFINITION,
            FREQUENCY_KEY => attrs[:frequency],
            "Assigned person" => attrs[:assigned_person],
            "Post" => attrs[:post]
          }
        )
        set_cell!(row:, property: properties.fetch("Frequency"), value: FREQUENCIES.fetch(attrs[:frequency]))
        set_cell!(row:, property: properties.fetch("Assigned person"), value: attrs[:assigned_person])
        set_cell!(row:, property: properties.fetch("Post"), value: attrs[:post])
      end

      def normalize_definition_attributes(attributes)
        raw = attributes.to_h
        frequency = raw["frequency"].to_s
        {
          title: raw["title"].to_s.strip,
          frequency: FREQUENCIES.key?(frequency) ? frequency : "weekly_mon_sun",
          assigned_person: raw["assigned_person"].to_s.strip,
          post: raw["post"].to_s.strip
        }
      end

      def archive_definition!(database:, id:)
        row = database.db_rows.active.find_by(id:)
        return unless definition_row?(row)

        row.archive!
      end

      def entry_metadata(definition:, period:)
        {
          ROW_TYPE_KEY => ROW_TYPE_ENTRY,
          DEFINITION_ID_KEY => definition.id,
          PERIOD_START_KEY => period.start_date.iso8601,
          PERIOD_END_KEY => period.end_date.iso8601
        }
      end

      def set_cell!(row:, property:, value:)
        cell = row.db_cells.find_or_initialize_by(db_property: property)
        cell.value_text = value.to_s
        cell.save!
      end
    end
  end
end
