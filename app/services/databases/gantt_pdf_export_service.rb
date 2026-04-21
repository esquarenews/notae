require "prawn"

module Databases
  class GanttPdfExportService
    Result = Struct.new(:pdf, keyword_init: true)

    PAGE_SIZE = "A4".freeze
    PAGE_LAYOUT = :landscape
    PAGE_MARGIN = 26
    LABEL_COLUMN_WIDTH = 160.0
    COLUMN_GAP = 14.0
    TITLE_HEIGHT = 20.0
    TITLE_GAP = 10.0
    HEADER_HEIGHT = 26.0
    HEADER_GAP = 12.0
    ROW_HEIGHT = 28.0
    ROW_GAP = 8.0
    TRACK_HEIGHT = 14.0
    STATUS_HEIGHT = 14.0
    SWATCH_SIZE = 14.0
    CORNER_RADIUS = 6.0
    BORDER_COLOR = "E7E5E4".freeze
    TEXT_COLOR = "292524".freeze
    MUTED_TEXT_COLOR = "57534E".freeze
    SURFACE_COLOR = "FCFCFB".freeze
    FONT_FILE = Rails.root.join("vendor/fonts/Manrope-wght.ttf").freeze

    STATUS_STYLES = {
      "not started" => { fg: "9A3412", bg: "FDBA74" },
      "started" => { fg: "166534", bg: "BBF7D0" },
      "overdue" => { fg: "991B1B", bg: "FECACA" },
      "hold" => { fg: "6B21A8", bg: "E9D5FF" },
      "done" => { fg: "4B5563", bg: "E5E7EB" },
      "__unset__" => { fg: "1D4ED8", bg: "DBEAFE" }
    }.freeze

    class << self
      def call(database:, gantt_data:)
        new(database:, gantt_data:).call
      end
    end

    def initialize(database:, gantt_data:)
      @database = database
      @gantt_data = gantt_data
    end

    def call
      pdf = Prawn::Document.new(
        page_size: PAGE_SIZE,
        page_layout: PAGE_LAYOUT,
        margin: PAGE_MARGIN,
        info: {
          Title: [ database.name.presence || "Gantt", "Gantt chart" ].join(" - ")
        }
      )
      register_fonts(pdf)
      pdf.font(pdf_font_family)

      if gantt_data.eligible?
        draw_chart(pdf)
      else
        draw_empty_state(pdf)
      end

      Result.new(pdf: pdf.render)
    end

    private

    attr_reader :database, :gantt_data

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

    def draw_chart(pdf)
      tasks_per_page = [ ((pdf.bounds.height - TITLE_HEIGHT - TITLE_GAP - HEADER_HEIGHT - HEADER_GAP) / (ROW_HEIGHT + ROW_GAP)).floor, 1 ].max
      gantt_data.tasks.each_slice(tasks_per_page).with_index do |tasks, index|
        pdf.start_new_page unless index.zero?
        draw_chart_page(pdf, tasks)
      end
    end

    def draw_chart_page(pdf, tasks)
      fill_page_background(pdf)
      draw_title(pdf)
      pdf.move_down TITLE_GAP

      top = pdf.cursor
      left = pdf.bounds.left
      timeline_left = left + LABEL_COLUMN_WIDTH + COLUMN_GAP
      timeline_width = pdf.bounds.right - timeline_left
      header_top = top

      draw_header(pdf, left:, top: header_top, timeline_left:, timeline_width:)

      current_top = header_top - HEADER_HEIGHT - HEADER_GAP
      tasks.each do |task|
        draw_row(pdf, task:, left:, top: current_top, timeline_left:, timeline_width:)
        current_top -= ROW_HEIGHT + ROW_GAP
      end

      pdf.move_cursor_to([ current_top, pdf.bounds.bottom ].max)
    end

    def draw_title(pdf)
      pdf.fill_color TEXT_COLOR
      pdf.font_size 14
      pdf.text(pdf_title, align: :left)
    end

    def draw_header(pdf, left:, top:, timeline_left:, timeline_width:)
      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 8
      pdf.text_box("Task", at: [ left, top - 3 ], width: LABEL_COLUMN_WIDTH, height: 12)

      draw_rounded_box(
        pdf,
        left: timeline_left,
        top: top,
        width: timeline_width,
        height: HEADER_HEIGHT,
        fill_color: SURFACE_COLOR,
        stroke_color: BORDER_COLOR
      )

      cursor_x = timeline_left
      gantt_data.ticks.each_with_index do |tick, index|
        tick_width = timeline_width * (tick.width_pct / 100.0)

        unless index.zero?
          pdf.stroke_color BORDER_COLOR
          pdf.line_width = 0.7
          pdf.stroke_line [ cursor_x, top ], [ cursor_x, top - HEADER_HEIGHT ]
        end

        pdf.fill_color MUTED_TEXT_COLOR
        pdf.font_size 7
        pdf.text_box(
          tick.label.to_s,
          at: [ cursor_x + 3, top - 8 ],
          width: [ tick_width - 6, 10 ].max,
          height: 10,
          align: :center,
          valign: :center,
          overflow: :shrink_to_fit,
          min_font_size: 5
        )

        cursor_x += tick_width
      end
    end

    def draw_row(pdf, task:, left:, top:, timeline_left:, timeline_width:)
      pdf.fill_color TEXT_COLOR
      pdf.font_size 9.5
      pdf.text_box(
        task.title.to_s,
        at: [ left, top ],
        width: LABEL_COLUMN_WIDTH,
        height: 13,
        overflow: :truncate
      )

      detail_bottom = top - 26
      draw_status_meta(pdf, task:, left:, bottom: detail_bottom)
      draw_track(pdf, task:, left: timeline_left, bottom: detail_bottom, width: timeline_width)
    end

    def draw_status_meta(pdf, task:, left:, bottom:)
      draw_rounded_box(
        pdf,
        left: left,
        top: bottom + SWATCH_SIZE,
        width: SWATCH_SIZE,
        height: SWATCH_SIZE,
        fill_color: task.color_hex.delete("#"),
        stroke_color: blend_hex(task.color_hex, BORDER_COLOR, 0.35),
        radius: 5
      )

      label = task.status_label.to_s.strip.presence || "No status"
      style = STATUS_STYLES.fetch(task.status_key.to_s, STATUS_STYLES.fetch("__unset__"))
      pill_left = left + SWATCH_SIZE + 5
      pill_width = [ pdf.width_of(label, size: 7.2) + 12, 50 ].max
      pill_bg = blend_hex(style.fetch(:bg), "FFFFFF", 0.62)
      pdf.fill_color pill_bg
      pdf.stroke_color pill_bg
      pdf.fill_and_stroke_rounded_rectangle [ pill_left, bottom + STATUS_HEIGHT ], pill_width, STATUS_HEIGHT, 6
      pdf.fill_color style.fetch(:fg)
      pdf.font_size 7.2
      pdf.text_box(
        label,
        at: [ pill_left + 6, bottom + STATUS_HEIGHT - 3 ],
        width: pill_width - 12,
        height: 10,
        overflow: :truncate
      )
    end

    def draw_track(pdf, task:, left:, bottom:, width:)
      top = bottom + TRACK_HEIGHT

      draw_rounded_box(
        pdf,
        left: left,
        top: top,
        width: width,
        height: TRACK_HEIGHT,
        fill_color: SURFACE_COLOR,
        stroke_color: BORDER_COLOR
      )

      cursor_x = left
      gantt_data.ticks.each_with_index do |tick, index|
        tick_width = width * (tick.width_pct / 100.0)

        unless index.zero?
          pdf.stroke_color BORDER_COLOR
          pdf.line_width = 0.5
          pdf.stroke_line [ cursor_x, top ], [ cursor_x, bottom ]
        end

        cursor_x += tick_width
      end

      bar_left = left + (width * (task.left_pct / 100.0))
      bar_width = [ width * (task.width_pct / 100.0), 8 ].max

      draw_rounded_box(
        pdf,
        left: bar_left,
        top: top,
        width: bar_width,
        height: TRACK_HEIGHT,
        fill_color: blend_hex(task.color_hex, "FFFFFF", 0.26),
        stroke_color: blend_hex(task.color_hex, "0F172A", 0.72)
      )
    end

    def draw_empty_state(pdf)
      fill_page_background(pdf)
      draw_title(pdf)
      pdf.move_down TITLE_GAP
      pdf.fill_color TEXT_COLOR
      pdf.font_size 16
      pdf.text_box("Gantt chart unavailable", at: [ pdf.bounds.left, pdf.cursor ], width: pdf.bounds.width, height: 20)
      pdf.move_down 26
      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 10
      pdf.text(gantt_data.message.presence || "Add a start date and an end date column, then give at least one row both dates.")
    end

    def fill_page_background(pdf)
      pdf.canvas do
        page_width = pdf.page.dimensions[2]
        page_height = pdf.page.dimensions[3]
        pdf.fill_color "FFFFFF"
        pdf.fill_rectangle [ 0, page_height ], page_width, page_height
      end
    end

    def pdf_title
      database.name.presence || "Untitled grid"
    end

    def draw_rounded_box(pdf, left:, top:, width:, height:, fill_color:, stroke_color:, radius: CORNER_RADIUS)
      pdf.fill_color(fill_color.delete("#"))
      pdf.stroke_color(stroke_color.delete("#"))
      pdf.line_width = 0.8
      pdf.fill_and_stroke_rounded_rectangle([ left, top ], width, height, radius)
    end

    def blend_hex(primary, secondary, primary_weight)
      primary_rgb = hex_to_rgb(primary)
      secondary_rgb = hex_to_rgb(secondary)

      blended = primary_rgb.zip(secondary_rgb).map do |primary_component, secondary_component|
        ((primary_component * primary_weight) + (secondary_component * (1 - primary_weight))).round
      end

      rgb_to_hex(blended)
    end

    def hex_to_rgb(value)
      sanitized = value.to_s.delete("#")
      sanitized = sanitized.chars.map { |char| char * 2 }.join if sanitized.length == 3
      sanitized.scan(/../).map { |pair| pair.to_i(16) }
    end

    def rgb_to_hex(rgb)
      format("%02X%02X%02X", *rgb)
    end
  end
end
