module Databases
  class GraphChartDataBuilder
    Category = Struct.new(
      :row_id,
      :label,
      :short_label,
      :index,
      keyword_init: true
    )

    Point = Struct.new(
      :row_id,
      :category_index,
      :value,
      keyword_init: true
    )

    Series = Struct.new(
      :property_id,
      :name,
      :color_hex,
      :points,
      :total,
      keyword_init: true
    )

    AxisTick = Struct.new(
      :label,
      :value,
      :ratio,
      keyword_init: true
    )

    PieSlice = Struct.new(
      :row_id,
      :name,
      :short_label,
      :color_hex,
      :value,
      :fraction,
      :percentage,
      :start_angle,
      :end_angle,
      keyword_init: true
    )

    SeriesGraph = Struct.new(
      :series,
      :axis_ticks,
      :min_value,
      :max_value,
      :display_min,
      :display_max,
      :zero_ratio,
      keyword_init: true
    )

    Result = Struct.new(
      :eligible,
      :message,
      :chart_type,
      :show_values,
      :split_series,
      :categories,
      :series,
      :series_graphs,
      :axis_ticks,
      :min_value,
      :max_value,
      :display_min,
      :display_max,
      :zero_ratio,
      :pie_slices,
      keyword_init: true
    ) do
      def eligible?
        eligible
      end

      def cartesian?
        !pie?
      end

      def line?
        chart_type == "line"
      end

      def stats?
        chart_type == "stats"
      end

      def line_like?
        line? || stats?
      end

      def bar?
        chart_type == "bar"
      end

      def pie?
        chart_type == "pie"
      end

      def split_series?
        split_series
      end

      def split_series_available?
        !pie? && series.length > 1
      end
    end

    DEFAULT_SERIES_COLORS = %w[
      #2563EB
      #10B981
      #F97316
      #A855F7
      #EC4899
      #14B8A6
      #EAB308
      #EF4444
    ].freeze
    STATS_ASCENDING_COLOR = "#111111".freeze
    STATS_NON_ASCENDING_COLOR = "#DC2626".freeze
    COLOR_HEX_PATTERN = /\A#(?:[0-9A-F]{3}|[0-9A-F]{6})\z/i
    GRAPH_TYPES = %w[line bar pie stats].freeze
    LABEL_TRUNCATION_LENGTH = 18
    AXIS_TICK_COUNT = 5

    class << self
      def format_value(value)
        numeric = value.to_f
        return numeric.round.to_s if numeric.round(4) == numeric.round

        formatted = format("%.2f", numeric)
        formatted.sub(/\.?0+\z/, "")
      end

      def format_percentage(value)
        numeric = value.to_f.round(1)
        formatted = format("%.1f", numeric).sub(/\.0\z/, "")
        "#{formatted}%"
      end

      def stats_segment_color(from_value, to_value)
        to_value.to_f > from_value.to_f ? STATS_ASCENDING_COLOR : STATS_NON_ASCENDING_COLOR
      end

      def stats_point_color(points, point_index)
        points = Array(points)
        current_point = points[point_index]
        return STATS_NON_ASCENDING_COLOR if current_point.blank?

        if point_index.positive?
          return stats_segment_color(points[point_index - 1].value, current_point.value)
        end

        next_point = points[point_index + 1]
        return stats_segment_color(current_point.value, next_point.value) if next_point.present?

        STATS_NON_ASCENDING_COLOR
      end
    end

    def initialize(rows:, db_properties:, cells_by_key:, view_config: {})
      @rows = Array(rows)
      @db_properties = Array(db_properties)
      @cells_by_key = cells_by_key || {}
      @view_config = view_config.to_h
    end

    def call
      categories = build_categories
      series = build_series(categories)

      if series.empty?
        return Result.new(
          eligible: false,
          chart_type: chart_type,
          show_values: show_values?,
          split_series: false,
          categories: categories,
          series: [],
          series_graphs: [],
          pie_slices: [],
          message: "Add at least one visible column with numeric values to create a graph."
        )
      end

      scale = scale_for_points(series.flat_map(&:points))
      split_series = split_series_enabled?(series)
      series_graphs = split_series ? build_series_graphs(series) : []

      pie_slices = build_pie_slices(categories:, series:)
      if chart_type == "pie" && pie_slices.empty?
        return Result.new(
          eligible: false,
          chart_type: chart_type,
          show_values: show_values?,
          split_series: false,
          categories: categories,
          series: series,
          series_graphs: [],
          pie_slices: [],
          message: "Pie graph requires at least one series with a positive total."
        )
      end

      Result.new(
        eligible: true,
        chart_type: chart_type,
        show_values: show_values?,
        split_series: split_series,
        categories: categories,
        series: series,
        series_graphs: series_graphs,
        axis_ticks: scale.fetch(:axis_ticks),
        min_value: scale.fetch(:min_value),
        max_value: scale.fetch(:max_value),
        display_min: scale.fetch(:display_min),
        display_max: scale.fetch(:display_max),
        zero_ratio: scale.fetch(:zero_ratio),
        pie_slices: pie_slices
      )
    end

    private

    attr_reader :rows, :db_properties, :cells_by_key, :view_config

    def chart_type
      candidate = view_config["graph_type"].to_s
      GRAPH_TYPES.include?(candidate) ? candidate : "line"
    end

    def show_values?
      ActiveModel::Type::Boolean.new.cast(view_config["graph_show_values"])
    end

    def split_series_requested?
      ActiveModel::Type::Boolean.new.cast(view_config["graph_split_series"])
    end

    def build_categories
      rows.each_with_index.map do |row, index|
        title = row.title.to_s.strip.presence || "Untitled row"
        Category.new(
          row_id: row.id,
          label: title,
          short_label: truncate_label(title),
          index: index
        )
      end
    end

    def build_series(categories)
      series_properties.each_with_index.filter_map do |property, index|
        points = categories.filter_map do |category|
          value = numeric_cell_value(category.row_id, property)
          next if value.nil?

          Point.new(
            row_id: category.row_id,
            category_index: category.index,
            value: value
          )
        end
        next if points.empty?

        Series.new(
          property_id: property.id,
          name: property.name.to_s.strip.presence || "Series #{index + 1}",
          color_hex: color_for(property, index, points: points),
          points: points,
          total: points.sum(&:value)
        )
      end
    end

    def build_axis_ticks(min:, max:)
      range = max - min
      return [ AxisTick.new(label: self.class.format_value(min), value: min, ratio: 0.0) ] if range <= 0

      step = range / AXIS_TICK_COUNT.to_f
      (0..AXIS_TICK_COUNT).map do |index|
        value = min + (step * index)
        AxisTick.new(
          label: self.class.format_value(value),
          value: value,
          ratio: ratio_for(value, min: min, max: max)
        )
      end
    end

    def scale_for_points(points)
      values = Array(points).map(&:value)
      min_value = values.min
      max_value = values.max
      display_min = min_value.to_f < 0 ? min_value.to_f : 0.0
      display_max = resolve_display_max(min_value:, max_value:, display_min:)

      {
        min_value: min_value,
        max_value: max_value,
        display_min: display_min,
        display_max: display_max,
        zero_ratio: ratio_for(0.0, min: display_min, max: display_max),
        axis_ticks: build_axis_ticks(min: display_min, max: display_max)
      }
    end

    def build_pie_slices(categories:, series:)
      positive_rows = categories.filter_map.with_index do |category, index|
        value = series.sum do |entry|
          point = entry.points.find { |candidate| candidate.category_index == category.index }
          point&.value.to_f
        end
        next unless value.positive?

        {
          row_id: category.row_id,
          name: category.label,
          short_label: category.short_label,
          color_hex: pie_color_for(index),
          value: value
        }
      end

      total = positive_rows.sum { |entry| entry[:value] }
      return [] if total <= 0

      start_angle = -90.0
      positive_rows.map do |entry|
        fraction = entry[:value] / total.to_f
        percentage = fraction * 100.0
        end_angle = start_angle + (fraction * 360.0)
        slice = PieSlice.new(
          row_id: entry[:row_id],
          name: entry[:name],
          short_label: entry[:short_label],
          color_hex: entry[:color_hex],
          value: entry[:value],
          fraction: fraction,
          percentage: percentage,
          start_angle: start_angle,
          end_angle: end_angle
        )
        start_angle = end_angle
        slice
      end
    end

    def split_series_enabled?(series)
      split_series_requested? && chart_type != "pie" && series.length > 1
    end

    def build_series_graphs(series)
      Array(series).map do |entry|
        scale = scale_for_points(entry.points)
        SeriesGraph.new(
          series: entry,
          axis_ticks: scale.fetch(:axis_ticks),
          min_value: scale.fetch(:min_value),
          max_value: scale.fetch(:max_value),
          display_min: scale.fetch(:display_min),
          display_max: scale.fetch(:display_max),
          zero_ratio: scale.fetch(:zero_ratio)
        )
      end
    end

    def pie_color_for(index)
      DEFAULT_SERIES_COLORS[index % DEFAULT_SERIES_COLORS.length]
    end

    def series_properties
      db_properties.select { |property| numeric_property?(property) }
    end

    def numeric_property?(property)
      rows.any? { |row| !numeric_cell_value(row.id, property).nil? }
    end

    def numeric_cell_value(row_id, property)
      value_text = cells_by_key[[ row_id, property.id ]]&.value_text
      return nil if value_text.blank?

      Float(value_text.to_s.strip)
    rescue ArgumentError, TypeError
      nil
    end

    def color_for(property, index, points:)
      return stats_color_for(points) if chart_type == "stats"

      custom_color = normalized_custom_colors[property.id.to_s]
      return custom_color if custom_color.present?

      DEFAULT_SERIES_COLORS[index % DEFAULT_SERIES_COLORS.length]
    end

    def stats_color_for(points)
      first_value = Array(points).first&.value
      last_value = Array(points).last&.value

      self.class.stats_segment_color(first_value, last_value)
    end

    def normalized_custom_colors
      @normalized_custom_colors ||= begin
        raw = view_config["graph_series_colors"]
        if raw.respond_to?(:to_h)
          raw.to_h.each_with_object({}) do |(key, value), colors|
            normalized_value = value.to_s.strip.upcase
            next unless normalized_value.match?(COLOR_HEX_PATTERN)

            colors[key.to_s] = normalized_value
          end
        else
          {}
        end
      end
    end

    def truncate_label(label)
      return label if label.length <= LABEL_TRUNCATION_LENGTH

      "#{label.first(LABEL_TRUNCATION_LENGTH - 1)}…"
    end

    def resolve_display_max(min_value:, max_value:, display_min:)
      highest = max_value.to_f
      range = highest - display_min
      buffer = [ range.abs * 0.2, highest.abs * 0.2, 1.0 ].max
      display_max = highest + buffer
      display_max > display_min ? display_max : display_min + 1.0
    end

    def ratio_for(value, min:, max:)
      range = max - min
      return 0.0 if range <= 0

      ((value - min) / range.to_f).clamp(0.0, 1.0)
    end
  end
end
