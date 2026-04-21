require "prawn"

module Databases
  class GraphPdfExportService
    Result = Struct.new(:pdf, keyword_init: true)
    ChartData = Struct.new(
      :chart_type,
      :show_values,
      :categories,
      :series,
      :axis_ticks,
      :display_min,
      :display_max,
      :zero_ratio,
      :pie_slices,
      keyword_init: true
    ) do
      def pie?
        chart_type == "pie"
      end

      def stats?
        chart_type == "stats"
      end

      def line_like?
        %w[line stats].include?(chart_type)
      end
    end

    PAGE_SIZE = "A4".freeze
    PAGE_LAYOUT = :landscape
    PAGE_MARGIN = 26
    TITLE_GAP = 12.0
    CHART_HEIGHT = 230.0
    LEGEND_GAP = 16.0
    LEGEND_ROW_HEIGHT = 20.0
    LEGEND_SWATCH_SIZE = 12.0
    PIE_RADIUS = 90.0
    BORDER_COLOR = "E7E5E4".freeze
    TEXT_COLOR = "292524".freeze
    MUTED_TEXT_COLOR = "57534E".freeze
    SURFACE_COLOR = "FCFCFB".freeze
    GRID_COLOR = "D6D3D1".freeze
    FONT_FILE = Rails.root.join("vendor/fonts/Manrope-wght.ttf").freeze

    class << self
      def call(database:, graph_data:)
        new(database:, graph_data:).call
      end
    end

    def initialize(database:, graph_data:)
      @database = database
      @graph_data = graph_data
    end

    def call
      pdf = Prawn::Document.new(
        page_size: PAGE_SIZE,
        page_layout: PAGE_LAYOUT,
        margin: PAGE_MARGIN,
        info: {
          Title: [ database.name.presence || "Graph", "Graph view" ].join(" - ")
        }
      )
      register_fonts(pdf)
      pdf.font(pdf_font_family)

      if graph_data.eligible?
        draw_graph(pdf)
      else
        draw_empty_state(pdf)
      end

      Result.new(pdf: pdf.render)
    end

    private

    attr_reader :database, :graph_data

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

    def draw_graph(pdf)
      draw_chart_page(pdf, chart_data: graph_data)
      draw_split_series_pages(pdf) if graph_data.split_series?
    end

    def draw_chart_page(pdf, chart_data:, legend_items: nil, subtitle: nil)
      fill_page_background(pdf)
      draw_title(pdf, subtitle:)
      pdf.move_down TITLE_GAP

      if chart_data.pie?
        draw_pie_chart(pdf, chart_data:)
      else
        draw_cartesian_chart(pdf, chart_data:)
      end

      pdf.move_down LEGEND_GAP
      draw_legend(pdf, legend_items: legend_items || default_legend_items(chart_data))
    end

    def draw_split_series_pages(pdf)
      Array(graph_data.series_graphs).each do |series_graph|
        pdf.start_new_page
        draw_chart_page(
          pdf,
          chart_data: split_series_chart_data(series_graph),
          legend_items: [ series_graph.series ],
          subtitle: "Split graph - #{series_graph.series.name}"
        )
      end
    end

    def split_series_chart_data(series_graph)
      ChartData.new(
        chart_type: graph_data.chart_type,
        show_values: graph_data.show_values,
        categories: graph_data.categories,
        series: [ series_graph.series ],
        axis_ticks: series_graph.axis_ticks,
        display_min: series_graph.display_min,
        display_max: series_graph.display_max,
        zero_ratio: series_graph.zero_ratio,
        pie_slices: []
      )
    end

    def default_legend_items(chart_data)
      chart_data.pie? ? chart_data.pie_slices : chart_data.series
    end

    def draw_title(pdf, subtitle: nil)
      pdf.fill_color TEXT_COLOR
      pdf.font_size 14
      pdf.text(database.name.presence || "Untitled grid")

      return if subtitle.blank?

      pdf.move_down 4
      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 9
      pdf.text(subtitle)
    end

    def draw_cartesian_chart(pdf, chart_data:)
      left = pdf.bounds.left + 36
      top = pdf.cursor
      width = pdf.bounds.width - 56
      height = CHART_HEIGHT
      bottom = top - height
      plot_width = width
      slot_width = plot_width / [ chart_data.categories.length, 1 ].max.to_f
      value_range = [ chart_data.display_max - chart_data.display_min, 1.0 ].max
      baseline_y = bottom + (chart_data.zero_ratio.to_f * height)

      chart_data.axis_ticks.each do |tick|
        tick_y = bottom + (tick.ratio.to_f * height)
        pdf.stroke_color GRID_COLOR
        pdf.line_width = (tick.value.to_f.zero? ? 1.0 : 0.5)
        pdf.stroke_line [ left, tick_y ], [ left + plot_width, tick_y ]
        pdf.fill_color MUTED_TEXT_COLOR
        pdf.font_size 7
        pdf.draw_text tick.label.to_s, at: [ left - 32, tick_y - 3 ]
      end

      pdf.stroke_color BORDER_COLOR
      pdf.line_width = 0.9
      pdf.stroke_line [ left, bottom ], [ left, top ]
      pdf.stroke_line [ left, baseline_y ], [ left + plot_width, baseline_y ]

      if chart_data.line_like?
        draw_line_series(pdf, chart_data:, left:, bottom:, height:, slot_width:, value_range:)
      else
        draw_bar_series(pdf, chart_data:, left:, bottom:, baseline_y:, height:, slot_width:, value_range:)
      end

      draw_rotated_labels(pdf, chart_data:, left:, bottom:, slot_width:)
      pdf.move_cursor_to(bottom - 70)
    end

    def draw_line_series(pdf, chart_data:, left:, bottom:, height:, slot_width:, value_range:)
      chart_data.series.each do |series|
        points = series.points.map do |point|
          [
            left + (slot_width * point.category_index) + (slot_width / 2.0),
            bottom + (((point.value - chart_data.display_min) / value_range.to_f) * height)
          ]
        end
        next if points.empty?

        if chart_data.stats?
          series.points.each_cons(2).with_index do |(from_point, to_point), index|
            segment_color = Databases::GraphChartDataBuilder.stats_segment_color(from_point.value, to_point.value)
            pdf.stroke_color(segment_color.delete("#"))
            pdf.line_width = 2.0
            pdf.stroke_line points[index], points[index + 1]
          end
        else
          pdf.stroke_color(series.color_hex.delete("#"))
          pdf.line_width = 2.0
          points.each_cons(2) do |from_point, to_point|
            pdf.stroke_line from_point, to_point
          end
        end

        points.each_with_index do |(x, y), index|
          source_point = series.points[index]
          point_color =
            if chart_data.stats?
              Databases::GraphChartDataBuilder.stats_point_color(series.points, index)
            else
              series.color_hex
            end

          pdf.fill_color(point_color.delete("#"))
          pdf.fill_circle [ x, y ], 3.4
          next unless chart_data.show_values

          pdf.fill_color TEXT_COLOR
          pdf.font_size 7
          pdf.draw_text Databases::GraphChartDataBuilder.format_value(source_point.value), at: [ x - 10, y + 8 ]
        end
      end
    end

    def draw_bar_series(pdf, chart_data:, left:, bottom:, baseline_y:, height:, slot_width:, value_range:)
      series_count = [ chart_data.series.length, 1 ].max
      group_width = slot_width * 0.72
      inner_gap = 3.0
      bar_width = [ ((group_width - (inner_gap * (series_count - 1))) / series_count.to_f), 5.0 ].max

      chart_data.categories.each do |category|
        group_left = left + (slot_width * category.index) + (slot_width / 2.0) - (group_width / 2.0)

        chart_data.series.each_with_index do |series, series_index|
          point = series.points.find { |entry| entry.category_index == category.index }
          next if point.blank?

          bar_left = group_left + (series_index * (bar_width + inner_gap))
          bar_y = bottom + (((point.value - chart_data.display_min) / value_range.to_f) * height)
          rect_top = [ bar_y, baseline_y ].max
          rect_height = [ (baseline_y - bar_y).abs, 3.0 ].max

          draw_rounded_box(
            pdf,
            left: bar_left,
            top: rect_top,
            width: bar_width,
            height: rect_height,
            fill_color: blend_hex(series.color_hex, "FFFFFF", 0.24),
            stroke_color: blend_hex(series.color_hex, "0F172A", 0.72),
            radius: 4
          )

          next unless chart_data.show_values

          pdf.fill_color TEXT_COLOR
          pdf.font_size 7
          pdf.draw_text Databases::GraphChartDataBuilder.format_value(point.value), at: [ bar_left - 4, rect_top + 6 ]
        end
      end
    end

    def draw_rotated_labels(pdf, chart_data:, left:, bottom:, slot_width:)
      chart_data.categories.each do |category|
        x = left + (slot_width * category.index) + (slot_width / 2.0)
        y = bottom - 12
        pdf.fill_color MUTED_TEXT_COLOR
        pdf.rotate(38, origin: [ x, y ]) do
          pdf.font_size 7
          pdf.draw_text category.short_label.to_s, at: [ x, y ]
        end
      end
    end

    def draw_pie_chart(pdf, chart_data:)
      center_x = pdf.bounds.left + 190
      center_y = pdf.cursor - 120

      chart_data.pie_slices.each do |slice|
        if slice.fraction.to_f >= 0.999_999
          pdf.fill_color(blend_hex(slice.color_hex, "FFFFFF", 0.18))
          pdf.stroke_color(blend_hex(slice.color_hex, "0F172A", 0.72))
          pdf.line_width = 0.8
          pdf.fill_and_stroke_circle [ center_x, center_y ], PIE_RADIUS
        else
          fill_and_stroke_sector(
            pdf,
            center_x: center_x,
            center_y: center_y,
            radius: PIE_RADIUS,
            start_angle: slice.start_angle,
            end_angle: slice.end_angle,
            fill_color: blend_hex(slice.color_hex, "FFFFFF", 0.18),
            stroke_color: blend_hex(slice.color_hex, "0F172A", 0.72)
          )
        end

        next unless chart_data.show_values

        if slice.fraction.to_f >= 0.999_999
          label_x = center_x
          label_y = center_y
        else
          mid_angle = slice.start_angle + ((slice.end_angle - slice.start_angle) / 2.0)
          label_x = center_x + (Math.cos(mid_angle * Math::PI / 180.0) * PIE_RADIUS * 0.6)
          label_y = center_y + (Math.sin(mid_angle * Math::PI / 180.0) * PIE_RADIUS * 0.6)
        end
        pdf.fill_color TEXT_COLOR
        pdf.font_size 7
        pdf.draw_text Databases::GraphChartDataBuilder.format_percentage(slice.percentage), at: [ label_x - 12, label_y - 4 ]
      end

      pdf.move_cursor_to(center_y - PIE_RADIUS - 24)
    end

    def draw_legend(pdf, legend_items:)
      row_gap = 10.0
      available_width = pdf.bounds.width
      x = pdf.bounds.left
      y = pdf.cursor

      legend_items.each do |item|
        label_width = pdf.width_of(item.name.to_s, size: 8)
        item_width = LEGEND_SWATCH_SIZE + 8 + label_width + 12

        if x + item_width > pdf.bounds.left + available_width
          x = pdf.bounds.left
          y -= LEGEND_ROW_HEIGHT + row_gap
        end

        draw_rounded_box(
          pdf,
          left: x,
          top: y + LEGEND_SWATCH_SIZE,
          width: LEGEND_SWATCH_SIZE,
          height: LEGEND_SWATCH_SIZE,
          fill_color: item.color_hex.delete("#"),
          stroke_color: blend_hex(item.color_hex, BORDER_COLOR, 0.45),
          radius: 4
        )
        pdf.fill_color TEXT_COLOR
        pdf.font_size 8
        pdf.draw_text item.name.to_s, at: [ x + LEGEND_SWATCH_SIZE + 8, y + 1 ]

        x += item_width
      end

      pdf.move_cursor_to([ y - LEGEND_ROW_HEIGHT, pdf.bounds.bottom ].max)
    end

    def draw_empty_state(pdf)
      fill_page_background(pdf)
      draw_title(pdf)
      pdf.move_down TITLE_GAP
      pdf.fill_color TEXT_COLOR
      pdf.font_size 16
      pdf.text_box("Graph unavailable", at: [ pdf.bounds.left, pdf.cursor ], width: pdf.bounds.width, height: 20)
      pdf.move_down 26
      pdf.fill_color MUTED_TEXT_COLOR
      pdf.font_size 10
      pdf.text(graph_data.message.presence || "Add at least one numeric column with values to create a graph.")
    end

    def fill_page_background(pdf)
      pdf.canvas do
        page_width = pdf.page.dimensions[2]
        page_height = pdf.page.dimensions[3]
        pdf.fill_color "FFFFFF"
        pdf.fill_rectangle [ 0, page_height ], page_width, page_height
      end
    end

    def draw_rounded_box(pdf, left:, top:, width:, height:, fill_color:, stroke_color:, radius:)
      pdf.fill_color(fill_color.delete("#"))
      pdf.stroke_color(stroke_color.delete("#"))
      pdf.line_width = 0.8
      pdf.fill_and_stroke_rounded_rectangle([ left, top ], width, height, radius)
    end

    def fill_and_stroke_sector(pdf, center_x:, center_y:, radius:, start_angle:, end_angle:, fill_color:, stroke_color:)
      points = sector_points(center_x:, center_y:, radius:, start_angle:, end_angle:)
      pdf.fill_color(fill_color.delete("#"))
      pdf.stroke_color(stroke_color.delete("#"))
      pdf.line_width = 0.8
      pdf.fill_and_stroke_polygon(*points)
    end

    def sector_points(center_x:, center_y:, radius:, start_angle:, end_angle:)
      sweep = end_angle - start_angle
      segments = [ (sweep.abs / 10.0).ceil, 2 ].max
      points = [ [ center_x, center_y ] ]

      (0..segments).each do |index|
        angle = start_angle + ((sweep / segments.to_f) * index)
        radians = angle * Math::PI / 180.0
        points << [
          center_x + (Math.cos(radians) * radius),
          center_y + (Math.sin(radians) * radius)
        ]
      end

      points
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
