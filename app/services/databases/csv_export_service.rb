require "csv"

module Databases
  class CsvExportService
    class << self
      def call(database:, include_archived_rows: false, include_archived_metadata: false, rows: nil)
        new(
          database:,
          include_archived_rows:,
          include_archived_metadata:,
          rows:
        ).call
      end
    end

    def initialize(database:, include_archived_rows: false, include_archived_metadata: false, rows: nil)
      @database = database
      @include_archived_rows = include_archived_rows
      @include_archived_metadata = include_archived_metadata
      @rows = rows
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

    attr_reader :database, :include_archived_rows, :include_archived_metadata, :rows

    def column_headers
      headers = [ "Name" ]
      headers << "Archived at" if include_archived_metadata
      headers + properties.map(&:name)
    end

    def row_values(row)
      values = [ row.title ]
      values << row.archived_at&.iso8601 if include_archived_metadata
      values + properties.map { |db_property| cell_lookup.fetch([ row.id, db_property.id ], "") }
    end

    def properties
      @properties ||= database.db_properties.ordered.to_a
    end

    def active_rows
      @active_rows ||= begin
        return Array(rows) unless rows.nil?

        scope = database.db_rows
        scope = scope.active unless include_archived_rows
        scope.ordered.to_a
      end
    end

    def cell_lookup
      @cell_lookup ||= begin
        scope = DbCell.joins(:db_row).where(db_rows: { database_id: database.id })
        unless rows.nil?
          scope = scope.where(db_row_id: Array(rows).map(&:id))
        else
          scope = scope.where(db_rows: { archived_at: nil }) unless include_archived_rows
        end

        scope.each_with_object({}) do |db_cell, memo|
          memo[[ db_cell.db_row_id, db_cell.db_property_id ]] = db_cell.value_text.to_s
        end
      end
    end
  end
end
