require "csv"

module Databases
  class CsvExportService
    class << self
      def call(database:)
        new(database:).call
      end
    end

    def initialize(database:)
      @database = database
    end

    def call
      CSV.generate(headers: true) do |csv|
        csv << column_headers
        active_rows.each do |row|
          csv << row_values(row)
        end
      end
    end

    private

    attr_reader :database

    def column_headers
      [ "Name" ] + properties.map(&:name)
    end

    def row_values(row)
      [ row.title ] + properties.map { |db_property| cell_lookup.fetch([ row.id, db_property.id ], "") }
    end

    def properties
      @properties ||= database.db_properties.ordered.to_a
    end

    def active_rows
      @active_rows ||= database.db_rows.active.ordered.to_a
    end

    def cell_lookup
      @cell_lookup ||= DbCell
                       .joins(:db_row)
                       .where(db_rows: { database_id: database.id, archived_at: nil })
                       .each_with_object({}) do |db_cell, memo|
        memo[[ db_cell.db_row_id, db_cell.db_property_id ]] = db_cell.value_text.to_s
      end
    end
  end
end
