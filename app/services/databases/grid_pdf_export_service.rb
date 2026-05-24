require "prawn"

module Databases
  class GridPdfExportService
    Result = Struct.new(:pdf, keyword_init: true)

    PAGE_SIZE = "A4".freeze
    PAGE_LAYOUT = :landscape
    PAGE_MARGIN = 28
    FONT_FILE = Rails.root.join("vendor/fonts/Manrope-wght.ttf").freeze
    TEXT_COLOR = "292524".freeze
    MUTED_TEXT_COLOR = "57534E".freeze
    BORDER_COLOR = "D6D3D1".freeze

    class << self
      def call(database:, rows: nil, date_range: {})
        new(database:, rows:, date_range:).call
      end
    end

    def initialize(database:, rows: nil, date_range: {})
      @database = database
      @rows = rows
      @date_range = date_range.to_h
    end

    def call
      pdf = Prawn::Document.new(
        page_size: PAGE_SIZE,
        page_layout: PAGE_LAYOUT,
        margin: PAGE_MARGIN,
        info: { Title: database.name.presence || "Grid export" }
      )
      register_fonts(pdf)
      pdf.font(pdf_font_family)
      draw_title(pdf)
      draw_rows(pdf)

      Result.new(pdf: pdf.render)
    end

    private

    attr_reader :database, :rows, :date_range

    def register_fonts(pdf)
      return unless FONT_FILE.exist?

      pdf.font_families.update(
        "Manrope" => {
          normal: FONT_FILE.to_s,
          bold: FONT_FILE.to_s
        }
      )
    end

    def pdf_font_family
      FONT_FILE.exist? ? "Manrope" : "Helvetica"
    end

    def draw_title(pdf)
      pdf.fill_color TEXT_COLOR
      pdf.font_size 15
      pdf.text(database.name.presence || "Grid export", style: :bold)
      pdf.move_down 4
      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 8
      pdf.text(subtitle)
      pdf.move_down 12
    end

    def draw_rows(pdf)
      header = column_headers.join(" | ")
      draw_line(pdf, header, bold: true)

      export_rows.each do |row|
        draw_line(pdf, row_values(row).join(" | "))
      end

      return if export_rows.any?

      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 10
      pdf.text("No rows in this date range.")
    end

    def draw_line(pdf, text, bold: false)
      pdf.fill_color bold ? TEXT_COLOR : MUTED_TEXT_COLOR
      pdf.font_size bold ? 8 : 7.5
      pdf.text(text.to_s, style: (bold ? :bold : :normal), overflow: :shrink_to_fit)
      pdf.stroke_color BORDER_COLOR
      pdf.stroke_horizontal_rule
      pdf.move_down 5
    end

    def subtitle
      start_date = date_range[:start_date]
      end_date = date_range[:end_date]
      if start_date.present? || end_date.present?
        "Date range: #{start_date || "Any"} to #{end_date || "Any"}"
      else
        "Exported #{Time.zone.today}"
      end
    end

    def column_headers
      [ "Name" ] + properties.map(&:name)
    end

    def row_values(row)
      [ row.title ] + properties.map { |property| cell_lookup.fetch([ row.id, property.id ], "") }
    end

    def properties
      @properties ||= database.db_properties.ordered.to_a
    end

    def export_rows
      @export_rows ||= rows.nil? ? database.db_rows.active.ordered.to_a : Array(rows)
    end

    def cell_lookup
      @cell_lookup ||= DbCell
        .where(db_row_id: export_rows.map(&:id), db_property_id: properties.map(&:id))
        .each_with_object({}) do |cell, memo|
          memo[[ cell.db_row_id, cell.db_property_id ]] = cell.value_text.to_s
        end
    end
  end
end
