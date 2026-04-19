module Notae
  class RequestPerformanceStore
    MAX_SAMPLES = 20
    SLOW_REQUEST_THRESHOLD_MS = 500.0
    DEFAULT_BUDGET = {
      total_ms: 800.0,
      sql_ms: 250.0,
      sql_queries: 60
    }.freeze
    ACTION_BUDGETS = {
      "WorkspaceHomeController#show" => {
        total_ms: 700.0,
        sql_ms: 180.0,
        sql_queries: 45
      },
      "WorkspaceSidebarSectionsController#show" => {
        total_ms: 500.0,
        sql_ms: 140.0,
        sql_queries: 35
      },
      "KalendariumController#show" => {
        total_ms: 900.0,
        sql_ms: 300.0,
        sql_queries: 80
      }
    }.freeze
    MEMORY_STORE_MUTEX = Mutex.new

    class << self
      def record!(workspace_id:, sample:)
        return if workspace_id.blank?

        samples = fetch(workspace_id: workspace_id, limit: MAX_SAMPLES)
        normalized = normalize_sample(sample)
        updated_samples = [ normalized, *samples ].first(MAX_SAMPLES)

        write(cache_key(workspace_id), updated_samples)
      end

      def fetch(workspace_id:, limit: MAX_SAMPLES)
        Array(read(cache_key(workspace_id))).map { |sample| normalize_sample(sample) }.first(limit)
      end

      def clear!(workspace_id:)
        delete(cache_key(workspace_id))
      end

      def budget_for(action:)
        DEFAULT_BUDGET.merge(ACTION_BUDGETS.fetch(action.to_s, {}))
      end

      def budget_breaches(sample)
        normalized = normalize_sample(sample)
        budget = budget_for(action: normalized[:action])
        breaches = []

        breaches << "total time" if normalized[:total_ms] > budget[:total_ms].to_f
        breaches << "sql time" if normalized[:sql_ms] > budget[:sql_ms].to_f
        breaches << "sql queries" if normalized[:sql_queries] > budget[:sql_queries].to_i
        breaches
      end

      def budget_status(sample)
        budget_breaches(sample).any? ? :over_budget : :healthy
      end

      private

      def read(key)
        return Rails.cache.read(key) if cache_backend_available?

        MEMORY_STORE_MUTEX.synchronize { memory_store[key] }
      end

      def write(key, value)
        if cache_backend_available?
          Rails.cache.write(key, value, expires_in: 14.days)
        else
          MEMORY_STORE_MUTEX.synchronize { memory_store[key] = value }
        end
      end

      def delete(key)
        if cache_backend_available?
          Rails.cache.delete(key)
        else
          MEMORY_STORE_MUTEX.synchronize { memory_store.delete(key) }
        end
      end

      def cache_backend_available?
        !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      end

      def cache_key(workspace_id)
        "notae/request_performance/#{workspace_id}"
      end

      def memory_store
        @memory_store ||= {}
      end

      def normalize_sample(sample)
        payload = sample.to_h.stringify_keys

        {
          action: payload["action"].to_s,
          path: payload["path"].to_s,
          total_ms: payload["total_ms"].to_f.round(1),
          sql_queries: payload["sql_queries"].to_i,
          sql_ms: payload["sql_ms"].to_f.round(1),
          status: payload["status"].to_i,
          recorded_at: cast_time(payload["recorded_at"]) || Time.current
        }
      end

      def cast_time(value)
        return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
