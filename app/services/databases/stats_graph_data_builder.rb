module Databases
  class StatsGraphDataBuilder
    AGGREGATION_PERIODS = {
      "weekly" => "Weekly",
      "monthly" => "Monthly",
      "quarterly" => "Quarterly",
      "annual" => "Annual"
    }.freeze
    DEFAULT_PERIOD_COUNT = 12
    MIN_PERIOD_COUNT = 4
    MAX_PERIOD_COUNT = 52
    MAX_PERIOD_COUNT_BY_AGGREGATION = {
      "weekly" => 52,
      "monthly" => 60,
      "quarterly" => 80,
      "annual" => 100
    }.freeze

    def self.max_period_count_for(aggregation_period)
      MAX_PERIOD_COUNT_BY_AGGREGATION.fetch(aggregation_period.to_s, MAX_PERIOD_COUNT)
    end

    Result = Struct.new(
      :definition,
      :aggregation_period,
      :period_count,
      :range_start_date,
      :range_end_date,
      :graph,
      :assigned_person,
      :division,
      :description,
      keyword_init: true
    ) do
      def title
        definition&.title.to_s
      end
    end

    def initialize(database:, definition:, date:, aggregation_period: nil, period_count: nil, range_start_date: nil, range_end_date: nil)
      @database = database
      @definition = definition
      @date = date
      @aggregation_period = normalize_aggregation_period(aggregation_period)
      @period_count = normalize_period_count(period_count)
      @range_start_date = parse_date(range_start_date)
      @range_end_date = parse_date(range_end_date)
    end

    def call
      periods = graph_periods
      values = values_for(periods)
      categories = periods.each_with_index.map do |period, index|
        GraphChartDataBuilder::Category.new(
          row_id: "#{period.fetch(:start_date).iso8601}:#{period.fetch(:end_date).iso8601}",
          label: period.fetch(:label),
          short_label: period.fetch(:short_label),
          index: index
        )
      end
      points = values.each_with_index.map do |value, index|
        GraphChartDataBuilder::Point.new(row_id: categories[index].row_id, category_index: index, value: value)
      end
      series = [
        GraphChartDataBuilder::Series.new(
          property_id: "stats-value",
          name: definition.title,
          color_hex: GraphChartDataBuilder.stats_segment_color(points.first&.value, points.last&.value),
          points: points,
          total: points.sum(&:value)
        )
      ]
      scale = scale_for(values)

      Result.new(
        definition: definition,
        aggregation_period: aggregation_period,
        period_count: periods.length,
        range_start_date: range_start_date,
        range_end_date: range_end_date,
        graph: GraphChartDataBuilder::Result.new(
          eligible: true,
          message: nil,
          chart_type: "stats",
          show_values: false,
          split_series: false,
          categories: categories,
          series: series,
          series_graphs: [],
          axis_ticks: scale.fetch(:axis_ticks),
          min_value: values.min,
          max_value: values.max,
          display_min: scale.fetch(:display_min),
          display_max: scale.fetch(:display_max),
          zero_ratio: ratio_for(0.0, min: scale.fetch(:display_min), max: scale.fetch(:display_max)),
          pie_slices: []
        ),
        assigned_person: StatsTemplateService.cell_value(definition, "Assigned person"),
        division: StatsTemplateService.cell_value(definition, "Division"),
        description: StatsTemplateService.cell_value(definition, "Description")
      )
    end

    private

    attr_reader :database, :definition, :date, :aggregation_period, :period_count, :range_start_date, :range_end_date

    def graph_periods
      return range_periods if explicit_range?

      periods = [ period_for(date) ]

      (period_count - 1).times do
        periods << previous_period(periods.last.fetch(:start_date))
      end

      periods.reverse
    end

    def range_periods
      start_boundary = [ range_start_date, range_end_date ].min
      end_boundary = [ range_start_date, range_end_date ].max
      periods = [ period_for(start_boundary) ]

      while periods.last.fetch(:end_date) < end_boundary
        periods << next_period(periods.last.fetch(:start_date))
      end

      periods
    end

    def period_for(period_date)
      case aggregation_period
      when "monthly"
        start_date = period_date.beginning_of_month
        end_date = period_date.end_of_month
        { start_date: start_date, end_date: end_date, label: end_date.strftime("%d %b %Y"), short_label: end_date.strftime("%d %b") }
      when "quarterly"
        quarter_month = (((period_date.month - 1) / 3) * 3) + 1
        start_date = Date.new(period_date.year, quarter_month, 1)
        end_date = (start_date + 3.months) - 1.day
        { start_date: start_date, end_date: end_date, label: end_date.strftime("%d %b %Y"), short_label: end_date.strftime("%d %b") }
      when "annual"
        start_date = period_date.beginning_of_year
        end_date = period_date.end_of_year
        { start_date: start_date, end_date: end_date, label: end_date.strftime("%d %b %Y"), short_label: end_date.strftime("%d %b") }
      else
        period = StatsTemplateService.period_for(date: period_date, frequency: StatsTemplateService.frequency_for(definition))
        start_date = period.start_date
        end_date = period.end_date
        { start_date: start_date, end_date: end_date, label: end_date.strftime("%d %b %Y"), short_label: end_date.strftime("%d %b") }
      end
    end

    def next_period(start_date)
      case aggregation_period
      when "monthly"
        period_for(start_date + 1.month)
      when "quarterly"
        period_for(start_date + 3.months)
      when "annual"
        period_for(start_date + 1.year)
      else
        period_for(start_date + 1.week)
      end
    end

    def previous_period(start_date)
      case aggregation_period
      when "monthly"
        period_for(start_date - 1.month)
      when "quarterly"
        period_for(start_date - 3.months)
      when "annual"
        period_for(start_date - 1.year)
      else
        period_for(start_date - 1.week)
      end
    end

    def values_for(periods)
      entries = database.db_rows
        .where("data_json ->> ? = ?", StatsTemplateService::ROW_TYPE_KEY, StatsTemplateService::ROW_TYPE_ENTRY)
        .where("data_json ->> ? = ?", StatsTemplateService::DEFINITION_ID_KEY, definition.id)
        .includes(db_cells: :db_property)
        .to_a
      value_property = database.db_properties.find_by(name: "Value")

      periods.map do |period|
        entries.sum do |entry|
          value = value_for(entry, value_property)
          next 0.0 if value.nil?

          value * overlap_ratio(entry_period(entry), period)
        end
      end
    end

    def value_for(entry, value_property)
      raw_value = if value_property.present?
        entry.db_cells.find { |cell| cell.db_property_id == value_property.id }&.value_text
      else
        entry.data_json.to_h["Value"]
      end
      return nil if raw_value.blank?

      Float(raw_value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def entry_period(entry)
      metadata = entry.data_json.to_h
      start_date = Date.iso8601(metadata[StatsTemplateService::PERIOD_START_KEY].to_s)
      end_date = Date.iso8601(metadata[StatsTemplateService::PERIOD_END_KEY].to_s)
      end_date -= 1.day if StatsTemplateService.frequency_for(definition) == "weekly_thu_2pm" && end_date > start_date
      { start_date: start_date, end_date: end_date }
    rescue ArgumentError
      nil
    end

    def overlap_ratio(entry_period, graph_period)
      return 0.0 if entry_period.blank?

      entry_start = entry_period.fetch(:start_date)
      entry_end = entry_period.fetch(:end_date)
      graph_start = graph_period.fetch(:start_date)
      graph_end = graph_period.fetch(:end_date)
      overlap_start = [ entry_start, graph_start ].max
      overlap_end = [ entry_end, graph_end ].min
      return 0.0 if overlap_end < overlap_start

      entry_days = [ (entry_end - entry_start).to_i + 1, 1 ].max
      overlap_days = (overlap_end - overlap_start).to_i + 1
      overlap_days / entry_days.to_f
    end

    def scale_for(values)
      min_value = values.min.to_f
      max_value = values.max.to_f
      range = max_value - min_value
      margin = [ range * 0.1, 1.0 ].max
      lower = min_value <= margin ? 0.0 : [ min_value - margin, 0.0 ].max
      upper = max_value + margin
      upper = 1.0 if upper <= lower

      display_min, display_max, tick_step = nice_axis(min: lower, max: upper)
      tick_values = []
      current = display_min
      while current <= display_max + (tick_step / 2.0)
        tick_values << current
        current += tick_step
      end

      {
        display_min: display_min,
        display_max: display_max,
        axis_ticks: tick_values.map do |value|
          GraphChartDataBuilder::AxisTick.new(
            label: GraphChartDataBuilder.format_value(value),
            value: value,
            ratio: ratio_for(value, min: display_min, max: display_max)
          )
        end
      }
    end

    def nice_axis(min:, max:)
      range = [ max - min, 1.0 ].max
      step = nice_number(range / 5.0)
      display_min = min.zero? ? 0.0 : (min / step).floor * step
      display_max = (max / step).ceil * step
      [ display_min, display_max, step ]
    end

    def nice_number(value)
      exponent = Math.log10(value).floor
      fraction = value / (10**exponent)
      nice_fraction =
        if fraction <= 1
          1
        elsif fraction <= 2
          2
        elsif fraction <= 5
          5
        else
          10
        end
      nice_fraction * (10**exponent)
    end

    def ratio_for(value, min:, max:)
      range = max - min
      return 0.0 if range <= 0

      (value - min) / range.to_f
    end

    def normalize_aggregation_period(value)
      candidate = value.to_s
      AGGREGATION_PERIODS.key?(candidate) ? candidate : "weekly"
    end

    def normalize_period_count(value)
      return DEFAULT_PERIOD_COUNT if value.blank?

      value.to_i.clamp(MIN_PERIOD_COUNT, self.class.max_period_count_for(aggregation_period))
    rescue NoMethodError
      DEFAULT_PERIOD_COUNT
    end

    def explicit_range?
      range_start_date.present? && range_end_date.present?
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
