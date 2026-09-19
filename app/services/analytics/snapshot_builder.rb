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

    DAILY_ACTIVITY_SQL = <<~SQL.squish.freeze
      WITH expanded_activity_seconds AS (
        SELECT buckets.bucket_started_at, active_seconds.active_second
        FROM analytics_activity_buckets AS buckets
        CROSS JOIN LATERAL generate_series(
          buckets.segment_offset_seconds,
          buckets.segment_offset_seconds + buckets.duration_seconds - 1
        ) AS active_seconds(active_second)
        WHERE buckets.user_id = $1
          AND buckets.bucket_started_at BETWEEN $2 AND $3
          AND (
            ($5 AND (
              buckets.workspace_id = ANY($4)
              OR buckets.workspace_id IS NULL
            ))
            OR (NOT $5 AND buckets.workspace_id = $6)
          )
      ),
      distinct_activity_seconds AS (
        SELECT DISTINCT bucket_started_at, active_second
        FROM expanded_activity_seconds
      )
      SELECT DATE(bucket_started_at AT TIME ZONE 'UTC' AT TIME ZONE $7) AS activity_date,
             COUNT(*) AS total_seconds
      FROM distinct_activity_seconds
      GROUP BY activity_date
    SQL

    TOTAL_ACTIVITY_SQL = <<~SQL.squish.freeze
      WITH expanded_activity_seconds AS (
        SELECT buckets.bucket_started_at, active_seconds.active_second
        FROM analytics_activity_buckets AS buckets
        CROSS JOIN LATERAL generate_series(
          buckets.segment_offset_seconds,
          buckets.segment_offset_seconds + buckets.duration_seconds - 1
        ) AS active_seconds(active_second)
        WHERE buckets.user_id = $1
          AND buckets.bucket_started_at BETWEEN $2 AND $3
          AND (
            ($5 AND (
              buckets.workspace_id = ANY($4)
              OR buckets.workspace_id IS NULL
            ))
            OR (NOT $5 AND buckets.workspace_id = $6)
          )
      )
      SELECT COUNT(*)
      FROM (
        SELECT DISTINCT bucket_started_at, active_second
        FROM expanded_activity_seconds
      ) AS distinct_activity_seconds
    SQL

    SURFACE_ACTIVITY_SQL = <<~SQL.squish.freeze
      WITH expanded_activity_dimensions AS (
        SELECT buckets.bucket_started_at,
               active_seconds.active_second,
               buckets.surface AS dimension_value
        FROM analytics_activity_buckets AS buckets
        CROSS JOIN LATERAL generate_series(
          buckets.segment_offset_seconds,
          buckets.segment_offset_seconds + buckets.duration_seconds - 1
        ) AS active_seconds(active_second)
        WHERE buckets.user_id = $1
          AND buckets.bucket_started_at BETWEEN $2 AND $3
          AND (
            ($5 AND (
              buckets.workspace_id = ANY($4)
              OR buckets.workspace_id IS NULL
            ))
            OR (NOT $5 AND buckets.workspace_id = $6)
          )
      ),
      unique_activity_dimensions AS (
        SELECT DISTINCT bucket_started_at, active_second, dimension_value
        FROM expanded_activity_dimensions
      ),
      weighted_activity_dimensions AS (
        SELECT dimension_value,
               COUNT(*) OVER (
                 PARTITION BY bucket_started_at, active_second
               ) AS dimensions_in_second
        FROM unique_activity_dimensions
      )
      SELECT dimension_value,
             SUM(1.0 / dimensions_in_second) AS attributed_seconds
      FROM weighted_activity_dimensions
      GROUP BY dimension_value
    SQL

    WORKSPACE_ACTIVITY_SQL = <<~SQL.squish.freeze
      WITH expanded_activity_dimensions AS (
        SELECT buckets.bucket_started_at,
               active_seconds.active_second,
               buckets.workspace_id AS dimension_value
        FROM analytics_activity_buckets AS buckets
        CROSS JOIN LATERAL generate_series(
          buckets.segment_offset_seconds,
          buckets.segment_offset_seconds + buckets.duration_seconds - 1
        ) AS active_seconds(active_second)
        WHERE buckets.user_id = $1
          AND buckets.bucket_started_at BETWEEN $2 AND $3
          AND (
            ($5 AND (
              buckets.workspace_id = ANY($4)
              OR buckets.workspace_id IS NULL
            ))
            OR (NOT $5 AND buckets.workspace_id = $6)
          )
      ),
      unique_activity_dimensions AS (
        SELECT DISTINCT bucket_started_at, active_second, dimension_value
        FROM expanded_activity_dimensions
      ),
      weighted_activity_dimensions AS (
        SELECT dimension_value,
               COUNT(*) OVER (
                 PARTITION BY bucket_started_at, active_second
               ) AS dimensions_in_second
        FROM unique_activity_dimensions
      )
      SELECT dimension_value,
             SUM(1.0 / dimensions_in_second) AS attributed_seconds
      FROM weighted_activity_dimensions
      GROUP BY dimension_value
    SQL

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

    def record_scope(model, user_key:, range: date_range.time_range)
      model.where(user_key => user.id, workspace_id: workspace_ids, created_at: range)
    end

    def daily_activity_series
      totals = grouped_sum_by_day(date_range.time_range)
      each_date.map { |date| { date: date, seconds: totals.fetch(date, 0).to_i } }
    end

    def previous_activity_seconds
      capped_activity_seconds(date_range.previous_time_range)
    end

    def each_date
      (date_range.start_date..date_range.end_date).to_a
    end

    def grouped_sum_by_day(range)
      rows = connection.exec_query(
        DAILY_ACTIVITY_SQL,
        "Analytics daily activity",
        activity_query_binds(range, include_timezone: true)
      ).rows

      rows.to_h { |day, total| [ day.to_date, total.to_i ] }
    end

    def capped_activity_seconds(range)
      connection.exec_query(
        TOTAL_ACTIVITY_SQL,
        "Analytics total activity",
        activity_query_binds(range)
      ).rows.dig(0, 0).to_i
    end

    def capped_dimension_totals(range, dimension)
      binds = activity_query_binds(range)
      rows = case dimension
      when :surface
        connection.exec_query(SURFACE_ACTIVITY_SQL, "Analytics surface activity", binds).rows
      when :workspace_id
        connection.exec_query(WORKSPACE_ACTIVITY_SQL, "Analytics workspace activity", binds).rows
      else
        raise ArgumentError, "Unsupported analytics dimension: #{dimension.inspect}"
      end

      allocate_integer_seconds(rows, total: capped_activity_seconds(range))
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

    def activity_query_binds(range, include_timezone: false)
      binds = [
        query_bind("user_id", user.id, uuid_type),
        query_bind("range_start", range.begin, ActiveRecord::Type::DateTime.new),
        query_bind("range_end", range.end, ActiveRecord::Type::DateTime.new),
        query_bind("workspace_ids", workspace_ids, uuid_array_type),
        query_bind("all_scope", scope == "all", ActiveRecord::Type::Boolean.new),
        query_bind("workspace_id", workspace_ids.first, uuid_type)
      ]
      binds << query_bind("time_zone", analytics_time_zone, ActiveRecord::Type::String.new) if include_timezone
      binds
    end

    def query_bind(name, value, type)
      ActiveRecord::Relation::QueryAttribute.new(name, value, type)
    end

    def analytics_time_zone
      ActiveSupport::TimeZone[user.time_zone.presence || "UTC"]&.tzinfo&.name || "UTC"
    end

    def uuid_type
      @uuid_type ||= ActiveRecord::Type.lookup(:uuid, adapter: :postgresql)
    end

    def uuid_array_type
      @uuid_array_type ||= ActiveRecord::Type.lookup(:uuid, adapter: :postgresql, array: true)
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
      totals = capped_dimension_totals(date_range.time_range, :surface)
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
      activity = capped_dimension_totals(date_range.time_range, :workspace_id)
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
