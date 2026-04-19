module Notae
  class ScheduledTaskStore
    MEMORY_STORE_MUTEX = Mutex.new
    TASK_DEFINITIONS = {
      "epistularium:sync_due" => {
        label: "Epistularium sync timer",
        cadence_label: "Every 10 minutes",
        expected_interval_seconds: 10.minutes.to_i,
        stale_after_seconds: 15.minutes.to_i
      },
      "kalendarium:sync_due" => {
        label: "Kalendarium sync dispatcher",
        cadence_label: "Manual or external trigger"
      },
      "kalendarium:dispatch_reminders" => {
        label: "Kalendarium reminder dispatch",
        cadence_label: "Manual or external trigger"
      },
      "meetings:schedule_due" => {
        label: "Meeting maintenance dispatcher",
        cadence_label: "Manual or external trigger"
      },
      "meetings:reconcile_runs" => {
        label: "Meeting stale-run reconciler",
        cadence_label: "Manual or external trigger"
      },
      "meetings:retry_failed_processing" => {
        label: "Meeting failed-processing retry",
        cadence_label: "Manual or external trigger"
      }
    }.freeze

    class << self
      def track!(task_name, started_at: Time.current)
        started_time = cast_time(started_at) || Time.current
        record_started!(task_name:, recorded_at: started_time)

        result = yield

        record_succeeded!(task_name:, started_at: started_time, finished_at: Time.current)
        result
      rescue StandardError => error
        record_failed!(task_name:, started_at: started_time, finished_at: Time.current, error:)
        raise
      end

      def fetch(task_name:, reference_time: Time.current)
        definition = task_definition_for(task_name)
        normalized = normalize_state(task_name, read(cache_key(task_name)))

        definition.merge(normalized).merge(status: derive_status(normalized, definition, reference_time:))
      end

      def fetch_all(reference_time: Time.current)
        TASK_DEFINITIONS.keys.map { |task_name| fetch(task_name:, reference_time:) }
      end

      def clear!(task_name:)
        delete(cache_key(task_name))
      end

      def clear_all!
        TASK_DEFINITIONS.each_key { |task_name| clear!(task_name:) }
      end

      def record_started!(task_name:, recorded_at: Time.current)
        task_state = fetch_raw(task_name)
        task_state[:last_started_at] = cast_time(recorded_at) || Time.current
        write(cache_key(task_name), task_state)
      end

      def record_succeeded!(task_name:, started_at:, finished_at: Time.current)
        task_state = fetch_raw(task_name)
        finished_time = cast_time(finished_at) || Time.current
        started_time = cast_time(started_at) || finished_time

        task_state.merge!(
          last_started_at: started_time,
          last_finished_at: finished_time,
          last_succeeded_at: finished_time,
          last_duration_ms: duration_ms(started_time, finished_time),
          last_error: nil,
          last_error_class: nil,
          consecutive_failures: 0
        )

        write(cache_key(task_name), task_state)
      end

      def record_failed!(task_name:, started_at:, finished_at: Time.current, error:)
        task_state = fetch_raw(task_name)
        finished_time = cast_time(finished_at) || Time.current
        started_time = cast_time(started_at) || finished_time

        task_state.merge!(
          last_started_at: started_time,
          last_finished_at: finished_time,
          last_failed_at: finished_time,
          last_duration_ms: duration_ms(started_time, finished_time),
          last_error: error.message.to_s.presence,
          last_error_class: error.class.name,
          consecutive_failures: task_state[:consecutive_failures].to_i + 1
        )

        write(cache_key(task_name), task_state)
      end

      private

      def fetch_raw(task_name)
        normalize_state(task_name, read(cache_key(task_name)))
      end

      def normalize_state(task_name, value)
        payload = value.to_h.stringify_keys

        {
          task_name: task_name.to_s,
          last_started_at: cast_time(payload["last_started_at"]),
          last_finished_at: cast_time(payload["last_finished_at"]),
          last_succeeded_at: cast_time(payload["last_succeeded_at"]),
          last_failed_at: cast_time(payload["last_failed_at"]),
          last_duration_ms: payload["last_duration_ms"]&.to_f&.round(1),
          last_error: payload["last_error"].to_s.presence,
          last_error_class: payload["last_error_class"].to_s.presence,
          consecutive_failures: payload["consecutive_failures"].to_i
        }
      end

      def derive_status(task_state, definition, reference_time:)
        return :never_run if task_state[:last_started_at].blank?

        if task_state[:last_failed_at].present? &&
           (task_state[:last_succeeded_at].blank? || task_state[:last_failed_at] > task_state[:last_succeeded_at])
          return :failed
        end

        stale_after_seconds = definition[:stale_after_seconds].to_i
        if stale_after_seconds.positive? && task_state[:last_started_at] < reference_time - stale_after_seconds.seconds
          return :drifted
        end

        :healthy
      end

      def task_definition_for(task_name)
        TASK_DEFINITIONS.fetch(task_name.to_s) do
          {
            label: task_name.to_s.humanize,
            cadence_label: "Manual or external trigger",
            expected_interval_seconds: nil,
            stale_after_seconds: nil
          }
        end
      end

      def cache_key(task_name)
        "notae/scheduled_tasks/#{task_name}"
      end

      def duration_ms(started_at, finished_at)
        ((finished_at - started_at) * 1000.0).round(1)
      end

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

      def memory_store
        @memory_store ||= {}
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
