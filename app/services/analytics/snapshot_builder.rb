module Analytics
  class SnapshotBuilder
    Result = Struct.new(
      :user,
      :workspaces,
      :scope,
      :scope_label,
      :date_range,
      :active_seconds,
      :previous_active_seconds,
      :active_change_percent,
      :active_days,
      :average_active_seconds,
      :longest_streak_days,
      :peak_day,
      :daily_activity,
      :trend_series,
      :surface_breakdown,
      :content_counts,
      :content_total,
      :ai_summary,
      :ai_models,
      :workspace_breakdown,
      :tracking_enabled,
      :generated_at,
      keyword_init: true
    )

    CONTENT_METRICS = {
      notas_created: "Notas created",
      blocks_created: "Blocks added",
      grids_created: "Grids created",
      comments_posted: "Comments posted",
      calendar_events_created: "Calendar events",
      meetings_created: "Meetings captured",
      exports_created: "Exports"
    }.freeze

    class << self
      def call(user:, workspaces:, scope:, date_range:)
        new(user:, workspaces:, scope:, date_range:).call
      end
    end

    def initialize(user:, workspaces:, scope:, date_range:)
      @user = user
      @workspaces = Array(workspaces).uniq(&:id)
      @scope = scope.to_s == "all" ? "all" : "workspace"
      @date_range = date_range
    end

    def call
      daily_activity = daily_activity_series
      active_seconds = daily_activity.sum { |entry| entry[:seconds] }
      active_days = daily_activity.count { |entry| entry[:seconds].positive? }
      previous_active_seconds = previous_activity_seconds
      content_counts = build_content_counts
      ai_summary = build_ai_summary

      Result.new(
        user: user,
        workspaces: workspaces,
        scope: scope,
        scope_label: scope_label,
        date_range: date_range,
        active_seconds: active_seconds,
        previous_active_seconds: previous_active_seconds,
        active_change_percent: percentage_change(active_seconds, previous_active_seconds),
        active_days: active_days,
        average_active_seconds: active_days.zero? ? 0 : (active_seconds.to_f / active_days).round,
        longest_streak_days: longest_streak(daily_activity),
        peak_day: daily_activity.max_by { |entry| entry[:seconds] },
        daily_activity: daily_activity,
        trend_series: aggregate_trend(daily_activity),
        surface_breakdown: build_surface_breakdown(active_seconds),
        content_counts: content_counts,
        content_total: content_counts.sum { |entry| entry[:count] },
        ai_summary: ai_summary,
        ai_models: build_ai_models,
        workspace_breakdown: build_workspace_breakdown,
        tracking_enabled: scope == "all" ? workspaces.any?(&:analytics_enabled?) : workspaces.first&.analytics_enabled?,
        generated_at: Time.current
      ).freeze
    end

    private

    attr_reader :user, :workspaces, :scope, :date_range

    def workspace_ids
      @workspace_ids ||= workspaces.map(&:id)
    end

    def scope_label
      scope == "all" ? "All my workspaces" : workspaces.first&.name.to_s
    end

    def activity_scope(range = date_range.time_range)
      relation = AnalyticsActivityBucket.for_user(user).within(range)
      if scope == "all"
        relation.where(workspace_id: workspace_ids).or(relation.where(workspace_id: nil))
      else
        relation.where(workspace_id: workspace_ids.first)
      end
    end

    def record_scope(model, user_key:, range: date_range.time_range)
      model.where(user_key => user.id, workspace_id: workspace_ids, created_at: range)
    end

    def daily_activity_series
      totals = grouped_sum_by_day(activity_scope)
      each_date.map { |date| { date: date, seconds: totals.fetch(date, 0).to_i } }
    end

    def previous_activity_seconds
      capped_activity_seconds(activity_scope(date_range.previous_time_range))
    end

    def each_date
      (date_range.start_date..date_range.end_date).to_a
    end

    def grouped_sum_by_day(relation)
      seconds = distinct_activity_seconds_sql(relation)
      rows = connection.select_rows(<<~SQL.squish)
        SELECT #{day_sql("bucket_started_at")} AS activity_date, COUNT(*) AS total_seconds
        FROM (#{seconds}) AS distinct_activity_seconds
        GROUP BY activity_date
      SQL

      rows.to_h { |day, total| [ day.to_date, total.to_i ] }
    end

    def capped_activity_seconds(relation)
      connection.select_value(<<~SQL.squish).to_i
        SELECT COUNT(*)
        FROM (#{distinct_activity_seconds_sql(relation)}) AS distinct_activity_seconds
      SQL
    end

    def expanded_activity_seconds_sql(relation, dimension: nil)
      columns = [ :bucket_started_at, :segment_offset_seconds, :duration_seconds ]
      columns << dimension if dimension.present?
      dimension_sql = if dimension.present?
        ", source.#{connection.quote_column_name(dimension)} AS dimension_value"
      else
        ""
      end

      <<~SQL.squish
        SELECT source.bucket_started_at,
               active_seconds.active_second
               #{dimension_sql}
        FROM (#{relation.select(*columns).to_sql}) AS source
        CROSS JOIN LATERAL generate_series(
          source.segment_offset_seconds,
          source.segment_offset_seconds + source.duration_seconds - 1
        ) AS active_seconds(active_second)
      SQL
    end

    def distinct_activity_seconds_sql(relation)
      <<~SQL.squish
        SELECT DISTINCT bucket_started_at, active_second
        FROM (#{expanded_activity_seconds_sql(relation)}) AS expanded_activity_seconds
      SQL
    end

    def capped_dimension_totals(relation, dimension)
      rows = connection.select_rows(<<~SQL.squish)
        SELECT dimension_value, SUM(1.0 / dimensions_in_second) AS attributed_seconds
        FROM (
          SELECT dimension_value,
                 COUNT(*) OVER (PARTITION BY bucket_started_at, active_second) AS dimensions_in_second
          FROM (
            SELECT DISTINCT bucket_started_at, active_second, dimension_value
            FROM (#{expanded_activity_seconds_sql(relation, dimension:)}) AS expanded_activity_dimensions
          ) AS unique_activity_dimensions
        ) AS weighted_activity_dimensions
        GROUP BY dimension_value
      SQL

      allocate_integer_seconds(rows, total: capped_activity_seconds(relation))
    end

    def allocate_integer_seconds(rows, total:)
      allocations = rows.map do |value, raw_seconds|
        exact = BigDecimal(raw_seconds.to_s)
        { value: value, seconds: exact.floor, remainder: exact.frac }
      end
      remaining = total - allocations.sum { |entry| entry[:seconds] }
      allocations
        .sort_by { |entry| [ -entry[:remainder], entry[:value].to_s ] }
        .first(remaining)
        .each { |entry| entry[:seconds] += 1 }

      allocations.to_h { |entry| [ entry[:value], entry[:seconds] ] }
    end

    def day_sql(column)
      return "DATE(#{column})" unless connection.adapter_name.downcase.include?("postgres")

      timezone = ActiveSupport::TimeZone[user.time_zone.presence || "UTC"]&.tzinfo&.name || "UTC"
      "DATE(#{column} AT TIME ZONE 'UTC' AT TIME ZONE #{connection.quote(timezone)})"
    end

    def connection
      ApplicationRecord.connection
    end

    def aggregate_trend(daily_activity)
      grouped = daily_activity.group_by do |entry|
        case date_range.grouping
        when :week then entry[:date].beginning_of_week
        when :month then entry[:date].beginning_of_month
        else entry[:date]
        end
      end

      series = grouped.map do |date, entries|
        {
          date: date,
          label: trend_label(date),
          seconds: entries.sum { |entry| entry[:seconds] }
        }
      end

      series.each_with_index.map do |entry, index|
        previous_seconds = index.zero? ? nil : series[index - 1][:seconds]
        entry.merge(trend_comparison(current: entry[:seconds], previous: previous_seconds))
      end
    end

    def trend_label(date)
      case date_range.grouping
      when :week then date.strftime("%-d %b")
      when :month then date.strftime("%b")
      else date.strftime("%a %-d")
      end
    end

    def trend_comparison(current:, previous:)
      return { previous_seconds: nil, change_percent: nil, change_direction: :baseline, change_label: "—" } if previous.nil?
      return { previous_seconds: previous, change_percent: 0, change_direction: :flat, change_label: "No change" } if current == previous
      if previous.zero?
        return { previous_seconds: previous, change_percent: nil, change_direction: :up, change_label: "New" }
      end

      percent = (((current - previous).to_f / previous) * 100).round
      {
        previous_seconds: previous,
        change_percent: percent,
        change_direction: percent.positive? ? :up : :down,
        change_label: "#{percent.positive? ? "+" : ""}#{percent}%"
      }
    end

    def build_surface_breakdown(active_seconds)
      totals = capped_dimension_totals(activity_scope, :surface)
      AnalyticsActivityBucket::SURFACES.filter_map do |surface|
        seconds = totals.fetch(surface, 0).to_i
        next if seconds.zero?

        {
          surface: surface,
          label: AnalyticsActivityBucket.label_for(surface),
          seconds: seconds,
          percent: active_seconds.zero? ? 0 : ((seconds.to_f / active_seconds) * 100).round(1)
        }
      end.sort_by { |entry| -entry[:seconds] }
    end

    def build_content_counts
      notas = nota_scope
      counts = {
        notas_created: notas.count,
        blocks_created: record_scope(Block, user_key: :created_by_id).count,
        grids_created: record_scope(Database, user_key: :created_by_id).count,
        comments_posted: record_scope(Comment, user_key: :author_id).count,
        calendar_events_created: record_scope(KalendariumEvent, user_key: :created_by_id).count,
        meetings_created: record_scope(MeetingSession, user_key: :created_by_id).count,
        exports_created: record_scope(PageExport, user_key: :requested_by_id).count
      }

      CONTENT_METRICS.map do |key, label|
        { key: key, label: label, count: counts.fetch(key).to_i }
      end
    end

    def build_ai_summary
      usage = ai_usage_scope
      workflows = record_scope(WorkflowRun, user_key: :user_id)
                  .where(trigger_source: %w[ai_assistant automation_agent])

      {
        requests: usage.count,
        tokens: usage.sum(:total_tokens).to_i,
        generated_writes: usage.where(operation: AiUsageLog::OP_ASSISTANT_WRITE).count,
        completed_actions: workflows.where(status: WorkflowRun::STATUS_SUCCEEDED).count,
        models_used: usage.where.not(model: [ nil, "" ]).distinct.count(:model)
      }
    end

    def build_ai_models
      ai_usage_scope
        .where.not(model: [ nil, "" ])
        .group(:model)
        .count
        .map { |model, count| { model: model, count: count.to_i } }
        .sort_by { |entry| -entry[:count] }
        .first(6)
    end

    def ai_usage_scope
      record_scope(AiUsageLog, user_key: :user_id)
        .where.not(operation: [
          AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS,
          AiUsageLog::OP_KNOWLEDGE_SUGGESTION_FAILURE
        ])
    end

    def build_workspace_breakdown
      activity = capped_dimension_totals(activity_scope, :workspace_id)
      ai_calls = ai_usage_scope.group(:workspace_id).count
      pages = nota_scope.group(:workspace_id).count
      databases = record_scope(Database, user_key: :created_by_id).group(:workspace_id).count

      entries = workspaces.map do |workspace|
        {
          id: workspace.id,
          slug: workspace.slug,
          name: workspace.name,
          color: workspace.display_color,
          active_seconds: activity.fetch(workspace.id, 0).to_i,
          ai_requests: ai_calls.fetch(workspace.id, 0).to_i,
          items_created: pages.fetch(workspace.id, 0).to_i + databases.fetch(workspace.id, 0).to_i,
          tracking_enabled: workspace.analytics_enabled?
        }
      end

      if scope == "all" && activity.fetch(nil, 0).positive?
        entries << {
          id: nil,
          slug: nil,
          name: "App-wide & account",
          color: "#64748b",
          active_seconds: activity.fetch(nil),
          ai_requests: 0,
          items_created: 0,
          tracking_enabled: workspaces.any?(&:analytics_enabled?)
        }
      end

      entries.sort_by { |entry| [ -entry[:active_seconds], entry[:name].downcase ] }
    end

    def nota_scope
      linked_page_ids = Database
                        .where(workspace_id: workspace_ids)
                        .where.not(linked_page_id: nil)
                        .select(:linked_page_id)

      record_scope(Page, user_key: :created_by_id)
        .where(page_kind: "nota")
        .where.not(id: linked_page_ids)
    end

    def percentage_change(current, previous)
      return nil if previous.zero?

      (((current - previous).to_f / previous) * 100).round
    end

    def longest_streak(daily_activity)
      longest = 0
      current = 0

      daily_activity.each do |entry|
        current = entry[:seconds].positive? ? current + 1 : 0
        longest = [ longest, current ].max
      end

      longest
    end
  end
end
