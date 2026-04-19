# frozen_string_literal: true

module Notae
  class SessionEventStore
    MAX_EVENTS = 20
    MEMORY_STORE_MUTEX = Mutex.new

    class << self
      def record!(user_id:, event:)
        return if user_id.blank?

        events = fetch(user_id:, limit: MAX_EVENTS)
        normalized = normalize_event(event)
        write(cache_key(user_id), [ normalized, *events ].first(MAX_EVENTS))
      end

      def fetch(user_id:, limit: MAX_EVENTS)
        Array(read(cache_key(user_id))).map { |event| normalize_event(event) }.first(limit)
      end

      def clear!(user_id:)
        delete(cache_key(user_id))
      end

      private

      def normalize_event(event)
        payload = event.to_h.stringify_keys

        {
          reason: payload["reason"].to_s,
          session_store: payload["session_store"].to_s,
          path: payload["path"].to_s,
          request_method: payload["request_method"].to_s,
          approximate_session_bytes: payload["approximate_session_bytes"].to_i,
          session_key_count: payload["session_key_count"].to_i,
          error_class: payload["error_class"].to_s.presence,
          error_message: payload["error_message"].to_s.presence,
          recorded_at: cast_time(payload["recorded_at"]) || Time.current
        }
      end

      def cache_key(user_id)
        "notae/session_events/#{user_id}"
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
