module Databases
  class GanttChartDataBuilder
    Task = Struct.new(
      :row_id,
      :title,
      :start_date,
      :end_date,
      :status_key,
      :status_label,
      :color_hex,
      :left_pct,
      :width_pct,
      :length_days,
      keyword_init: true
    )

    Tick = Struct.new(
      :label,
      :width_pct,
      keyword_init: true
    )

    Result = Struct.new(
      :eligible,
      :message,
      :start_property,
      :end_property,
      :status_property,
      :range_start,
      :range_end,
      :scale,
      :ticks,
      :tasks,
      keyword_init: true
    ) do
      def eligible?
        eligible
      end
    end

    DEFAULT_STATUS_COLORS = {
      "not started" => "#F59E0B",
      "started" => "#10B981",
      "overdue" => "#EF4444",
      "hold" => "#A855F7",
      "done" => "#6B7280",
      "__unset__" => "#2563EB"
    }.freeze
    FALLBACK_STATUS_COLORS = %w[#2563EB #0F766E #C2410C #7C3AED #B91C1C #0891B2].freeze
    START_PROPERTY_PATTERNS = [
      /\Astart(?:\s+date)?\z/i,
      /\Abegin(?:\s+date)?\z/i,
      /\Afrom\z/i,
      /\Adate\s+created\z/i,
      /\Acreated(?:\s+date)?\z/i,
      /\Aestablished(?:\s+date)?\z/i
    ].freeze
    END_PROPERTY_PATTERNS = [
      /\Aend(?:\s+date)?\z/i,
      /\Adue(?:\s+date)?\z/i,
      /\Adeadline\z/i,
      /\Afinish(?:\s+date)?\z/i,
      /\Auntil\z/i
    ].freeze
    COLOR_HEX_PATTERN = /\A#(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i

    def initialize(rows:, db_properties:, cells_by_key:, view_config: {})
      @rows = Array(rows)
      @db_properties = Array(db_properties)
      @cells_by_key = cells_by_key || {}
      @view_config = view_config.to_h
    end

    def call
      start_property, end_property = resolve_date_properties
      unless start_property.present? && end_property.present?
        return Result.new(
          eligible: false,
          message: "Add both a start date and an end date column to create a Gantt chart."
        )
      end

      status_property = @db_properties.find { |property| property.select? && property.name.to_s.strip.casecmp("status").zero? }
      custom_colors = normalized_custom_colors
      tasks = build_tasks(
        start_property: start_property,
        end_property: end_property,
        status_property: status_property,
        custom_colors: custom_colors
      )

      if tasks.empty?
        return Result.new(
          eligible: false,
          start_property: start_property,
          end_property: end_property,
          status_property: status_property,
          message: "Add at least one row with both #{start_property.name} and #{end_property.name} to create a Gantt chart."
        )
      end

      range_start = tasks.map(&:start_date).min
      range_end = tasks.map(&:end_date).max
      total_days = [ (range_end - range_start).to_i + 1, 1 ].max
      scale = resolve_scale(total_days)
      ticks = build_ticks(range_start:, range_end:, total_days:, scale:)

      tasks.each do |task|
        offset_days = (task.start_date - range_start).to_i
        width_days = (task.end_date - task.start_date).to_i + 1
        task.left_pct = percentage(offset_days, total_days)
        task.width_pct = percentage(width_days, total_days)
        task.length_days = width_days
      end

      Result.new(
        eligible: true,
        start_property: start_property,
        end_property: end_property,
        status_property: status_property,
        range_start: range_start,
        range_end: range_end,
        scale: scale,
        ticks: ticks,
        tasks: tasks
      )
    end

    private

    def resolve_date_properties
      date_properties = @db_properties.select(&:date?)
      return [ nil, nil ] if date_properties.empty?

      start_property = resolve_property_by_patterns(date_properties, START_PROPERTY_PATTERNS)
      end_property = resolve_property_by_patterns(date_properties, END_PROPERTY_PATTERNS, except: start_property)

      if start_property.blank? && date_properties.size >= 2
        start_property = date_properties.first
      end

      if end_property.blank? && date_properties.size >= 2
        end_property = date_properties.find { |property| property.id != start_property&.id }
      end

      [ start_property, end_property ]
    end

    def resolve_property_by_patterns(properties, patterns, except: nil)
      properties.find do |property|
        next false if except.present? && property.id == except.id

        property_name = property.name.to_s.strip
        patterns.any? { |pattern| property_name.match?(pattern) }
      end
    end

    def build_tasks(start_property:, end_property:, status_property:, custom_colors:)
      @rows.filter_map do |row|
        start_date = parse_date(cell_value(row, start_property))
        end_date = parse_date(cell_value(row, end_property))
        next if start_date.blank? || end_date.blank?
        next if end_date < start_date

        raw_status = status_property.present? ? cell_value(row, status_property) : nil
        status_key = normalize_status(raw_status)
        Task.new(
          row_id: row.id,
          title: row.title.to_s.strip.presence || "Untitled row",
          start_date: start_date,
          end_date: end_date,
          status_key: status_key,
          status_label: raw_status.to_s.strip.presence || "No status",
          color_hex: row.gantt_color_hex || color_for(status_key, custom_colors)
        )
      end
    end

    def resolve_scale(total_days)
      return "day" if total_days <= 31
      return "week" if total_days <= 180

      "month"
    end

    def build_ticks(range_start:, range_end:, total_days:, scale:)
      case scale
      when "day"
        build_day_ticks(range_start:, range_end:, total_days:)
      when "week"
        build_week_ticks(range_start:, range_end:, total_days:)
      else
        build_month_ticks(range_start:, range_end:, total_days:)
      end
    end

    def build_day_ticks(range_start:, range_end:, total_days:)
      (range_start..range_end).map do |date|
        Tick.new(label: date.strftime("%-d %b"), width_pct: percentage(1, total_days))
      end
    end

    def build_week_ticks(range_start:, range_end:, total_days:)
      ticks = []
      cursor = range_start

      while cursor <= range_end
        tick_end = [ cursor + 6.days, range_end ].min
        ticks << Tick.new(
          label: cursor.strftime("%-d %b"),
          width_pct: percentage((tick_end - cursor).to_i + 1, total_days)
        )
        cursor = tick_end + 1.day
      end

      ticks
    end

    def build_month_ticks(range_start:, range_end:, total_days:)
      ticks = []
      cursor = range_start

      while cursor <= range_end
        tick_end = [ cursor.end_of_month, range_end ].min
        ticks << Tick.new(
          label: cursor.strftime("%b %Y"),
          width_pct: percentage((tick_end - cursor).to_i + 1, total_days)
        )
        cursor = tick_end + 1.day
      end

      ticks
    end

    def normalized_custom_colors
      raw_colors = @view_config["gantt_status_colors"]
      return {} unless raw_colors.respond_to?(:to_h)

      raw_colors.to_h.each_with_object({}) do |(key, value), colors|
        next unless value.to_s.match?(COLOR_HEX_PATTERN)

        colors[key.to_s] = value.to_s.upcase
      end
    end

    def color_for(status_key, custom_colors)
      return custom_colors[status_key] if custom_colors.key?(status_key)
      return DEFAULT_STATUS_COLORS[status_key] if DEFAULT_STATUS_COLORS.key?(status_key)

      FALLBACK_STATUS_COLORS[status_key.to_s.each_byte.sum % FALLBACK_STATUS_COLORS.length]
    end

    def normalize_status(value)
      normalized = value.to_s.strip.downcase
      normalized = DatabaseTablePresentation::TASK_STATUS_NORMALIZATION_MAP.fetch(normalized, normalized)
      normalized.presence || "__unset__"
    end

    def cell_value(row, property)
      return "" if row.blank? || property.blank?

      @cells_by_key[[ row.id, property.id ]]&.value_text.to_s
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def percentage(value, total)
      return 0.0 if total.to_f <= 0

      ((value.to_f / total.to_f) * 100).round(4)
    end
  end
end
