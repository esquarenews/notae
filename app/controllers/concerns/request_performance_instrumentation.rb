module RequestPerformanceInstrumentation
  extend ActiveSupport::Concern

  IGNORED_SQL_PAYLOAD_NAMES = %w[SCHEMA TRANSACTION CACHE].freeze
  IGNORED_SQL_PREFIXES = [
    "BEGIN",
    "COMMIT",
    "ROLLBACK",
    "SAVEPOINT",
    "RELEASE SAVEPOINT",
    "ROLLBACK TO SAVEPOINT"
  ].freeze

  included do
    class_attribute :request_performance_actions, instance_writer: false, default: []
    around_action :instrument_request_performance, if: :request_performance_enabled?
  end

  class_methods do
    def track_request_performance_for(*actions)
      self.request_performance_actions = actions.flatten.map(&:to_s)
    end
  end

  private

  def request_performance_enabled?
    return false unless Rails.env.development? || Rails.env.test?

    self.class.request_performance_actions.include?(action_name)
  end

  def instrument_request_performance
    counters = { queries: 0, sql_duration_ms: 0.0 }
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    subscriber = lambda do |_event_name, event_start, event_finish, _event_id, payload|
      next if payload[:cached]
      next if IGNORED_SQL_PAYLOAD_NAMES.include?(payload[:name].to_s)

      sql = payload[:sql].to_s.strip
      next if sql.blank?
      next if IGNORED_SQL_PREFIXES.any? { |prefix| sql.start_with?(prefix) }

      counters[:queries] += 1
      counters[:sql_duration_ms] += ((event_finish - event_start) * 1000.0)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      yield
    end
  ensure
    total_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0)
    sql_duration_ms = counters[:sql_duration_ms].round(1)
    total_duration_ms = total_duration_ms.round(1)
    action_label = "#{self.class.name}##{action_name}"

    response.set_header("X-Notae-Perf-Action", action_label)
    response.set_header("X-Notae-Perf-Total-Ms", total_duration_ms.to_s)
    response.set_header("X-Notae-Perf-Sql-Queries", counters[:queries].to_s)
    response.set_header("X-Notae-Perf-Sql-Ms", sql_duration_ms.to_s)

    Rails.logger.info(
      "[NOTAE PERF] action=#{action_label} total_ms=#{total_duration_ms} sql_queries=#{counters[:queries]} sql_ms=#{sql_duration_ms}"
    )
  end
end
