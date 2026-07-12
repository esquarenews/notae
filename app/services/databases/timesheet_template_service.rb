module Databases
  class TimesheetTemplateService
    TEMPLATE_NAME = "Time sheets".freeze
    STARTED_AT_PROPERTY = "Date/time clock started".freeze
    STOPPED_AT_PROPERTY = "Date/time clock stopped".freeze
    TOTAL_TIME_PROPERTY = "Calculated total time".freeze
    NOTES_PROPERTY = "Notes".freeze
    DONE_BY_PROPERTY = "Done by".freeze

    PROPERTIES = [
      [ STARTED_AT_PROPERTY, "text" ],
      [ STOPPED_AT_PROPERTY, "text" ],
      [ TOTAL_TIME_PROPERTY, "text" ],
      [ NOTES_PROPERTY, "text" ],
      [ DONE_BY_PROPERTY, "text" ]
    ].freeze

    PROPERTY_TYPES = PROPERTIES.each_with_object({}) do |(name, property_type), index|
      index[name.to_s.strip.downcase] = property_type
    end.freeze

    class << self
      def active?(database)
        database&.applied_template_name.to_s == TEMPLATE_NAME
      end

      def convertible?(database, properties: nil)
        props = Array(properties || database.db_properties.ordered.to_a)
        return true if props.empty?

        grouped_properties = props.group_by { |property| normalize_property_name(property.name) }
        grouped_properties.all? do |property_name, matching_properties|
          expected_type = PROPERTY_TYPES[property_name]
          next false if expected_type.blank? || !matching_properties.one?

          matching_property = matching_properties.first
          matching_property.property_type == expected_type ||
            (property_name == normalize_property_name(TOTAL_TIME_PROPERTY) && matching_property.number?)
        end
      end

      def ready?(properties:)
        normalized_types = Array(properties).each_with_object({}) do |property, index|
          index[normalize_property_name(property.name)] = property.property_type
        end

        PROPERTY_TYPES.all? do |property_name, property_type|
          normalized_types[property_name] == property_type
        end
      end

      def apply!(database:, table_view:)
        properties = PROPERTIES.map do |name, property_type|
          find_or_create_property!(database:, name:, property_type:)
        end

        seed_cells!(database:, properties:)
        configure_table_view!(table_view:, properties:)
        database.update!(database_template: nil, applied_template_name: TEMPLATE_NAME)
      end

      def date_range_from_params(params)
        {
          start_date: parse_date(params[:timesheet_start_date]),
          end_date: parse_date(params[:timesheet_end_date])
        }
      end

      def filtered_rows(database:, start_date: nil, end_date: nil)
        rows = database.db_rows.active.ordered.includes(:db_cells).to_a
        return rows if start_date.blank? && end_date.blank?

        started_property = property_by_name(database, STARTED_AT_PROPERTY)
        return [] if started_property.blank?

        rows.select do |row|
          started_at = parse_time(row.db_cells.find { |cell| cell.db_property_id == started_property.id }&.value_text)
          next false if started_at.blank?
          next false if start_date.present? && started_at.to_date < start_date
          next false if end_date.present? && started_at.to_date > end_date

          true
        end
      end

      def maybe_update_total_for!(cell)
        return unless cell&.db_property&.name.to_s.in?([ STARTED_AT_PROPERTY, STOPPED_AT_PROPERTY ])
        return unless active?(cell.db_row&.database)

        row = cell.db_row
        database = row.database
        started_property = property_by_name(database, STARTED_AT_PROPERTY)
        stopped_property = property_by_name(database, STOPPED_AT_PROPERTY)
        total_property = property_by_name(database, TOTAL_TIME_PROPERTY)
        return if started_property.blank? || stopped_property.blank? || total_property.blank?

        started_at = parse_time(cell_value(row:, property: started_property))
        stopped_at = parse_time(cell_value(row:, property: stopped_property))
        return if started_at.blank? || stopped_at.blank? || stopped_at < started_at

        total_property.update!(property_type: :text) if total_property.number?
        total_cell = row.db_cells.find_or_initialize_by(db_property: total_property)
        total_cell.value_text = format_elapsed_duration(stopped_at - started_at)
        total_cell.save! if total_cell.changed?
      end

      def active_timer(workspace:)
        return nil if workspace.blank?

        databases = workspace.databases.active
          .where(applied_template_name: TEMPLATE_NAME)
          .select(:id, :name)
          .order(:id)
          .to_a
        return nil if databases.empty?

        properties_by_database = DbProperty
          .where(database_id: databases.map(&:id))
          .select(:id, :database_id, :name)
          .to_a
          .group_by(&:database_id)

        databases.each do |database|
          properties = properties_by_database.fetch(database.id, [])
          started_property = property_from(properties, STARTED_AT_PROPERTY)
          stopped_property = property_from(properties, STOPPED_AT_PROPERTY)
          next if started_property.blank? || stopped_property.blank?

          timer = active_timer_for_database(
            database,
            started_property:,
            stopped_property:
          )
          return timer if timer.present?
        end

        nil
      end

      def parse_time(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        Time.zone.parse(raw)
      rescue ArgumentError
        nil
      end

      private

      def find_or_create_property!(database:, name:, property_type:)
        existing_property = database.db_properties.ordered.find do |property|
          normalize_property_name(property.name) == normalize_property_name(name)
        end
        if existing_property.present? && normalize_property_name(name) == normalize_property_name(TOTAL_TIME_PROPERTY)
          existing_property.update!(property_type:) unless existing_property.property_type == property_type
          return existing_property
        end

        return existing_property if existing_property.present? && existing_property.property_type == property_type

        if existing_property.present?
          existing_property.errors.add(:property_type, "must be #{property_type} to use the Time sheets template")
          raise ActiveRecord::RecordInvalid, existing_property
        end

        database.db_properties.create!(
          workspace: database.workspace,
          name: name,
          property_type: property_type
        )
      end

      def seed_cells!(database:, properties:)
        rows = database.db_rows.order(:created_at).to_a
        return if rows.empty? || properties.empty?

        existing_cells = DbCell
          .for_database(database)
          .where(db_row_id: rows.map(&:id), db_property_id: properties.map(&:id))
          .index_by { |cell| [ cell.db_row_id, cell.db_property_id ] }

        rows.each do |row|
          properties.each do |property|
            next if existing_cells.key?([ row.id, property.id ])

            DbCell.create!(workspace: database.workspace, db_row: row, db_property: property, value_text: "")
          end
        end
      end

      def configure_table_view!(table_view:, properties:)
        return if table_view.blank?

        config = table_view.config_json.to_h
        config["visible_property_ids"] = properties.map { |property| property.id.to_s }
        table_view.update!(config_json: config)
      end

      def property_by_name(database, name)
        database.db_properties.ordered.find { |property| normalize_property_name(property.name) == normalize_property_name(name) }
      end

      def active_timer_for_database(database, started_property:, stopped_property:)
        started_cell_join = DbRow.sanitize_sql_array(
          [
            <<~SQL.squish,
              INNER JOIN db_cells AS active_timer_started_cells
                ON active_timer_started_cells.db_row_id = db_rows.id
               AND active_timer_started_cells.db_property_id = ?
               AND active_timer_started_cells.value_text <> ''
            SQL
            started_property.id
          ]
        )
        stopped_row_ids = DbCell
          .where(db_property_id: stopped_property.id)
          .where("NULLIF(BTRIM(db_cells.value_text), '') IS NOT NULL")
          .select(:db_row_id)

        candidates = database.db_rows.active
          .joins(started_cell_join)
          .where.not(id: stopped_row_ids)
          .select("db_rows.*, active_timer_started_cells.value_text AS active_timer_started_at")
          .ordered

        candidates.each do |row|
          started_at = parse_time(row[:active_timer_started_at])
          next if started_at.blank?

          return {
            database: database,
            row: row,
            started_at: started_at
          }
        end

        nil
      end

      def property_from(properties, name)
        normalized_name = normalize_property_name(name)
        Array(properties).find { |property| normalize_property_name(property.name) == normalized_name }
      end

      def cell_value(row:, property:)
        row.db_cells.find { |cell| cell.db_property_id == property.id }&.value_text
      end

      def parse_date(value)
        raw = value.to_s.strip
        return nil if raw.blank?

        Date.iso8601(raw)
      rescue ArgumentError
        nil
      end

      def format_elapsed_duration(seconds)
        total_seconds = [ seconds.to_i, 0 ].max
        hours = total_seconds / 3600
        minutes = (total_seconds % 3600) / 60
        remaining_seconds = total_seconds % 60

        format("%02d:%02d:%02d", hours, minutes, remaining_seconds)
      end

      def normalize_property_name(name)
        name.to_s.strip.downcase
      end
    end
  end
end
