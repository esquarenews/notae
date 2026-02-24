module Api
  module V1
    class RateLimiter
      class << self
        def memory_counters
          @memory_counters ||= {}
        end

        def mutex
          @mutex ||= Mutex.new
        end
      end

      def self.allowed?(token:)
        new(token: token).allowed?
      end

      def initialize(token:)
        @token = token
      end

      def allowed?
        request_count <= limit
      end

      private

      attr_reader :token

      def request_count
        value = Rails.cache.increment(cache_key, 1, expires_in: window_seconds, initial: 0)
        return value if value.present?

        cached = Rails.cache.read(cache_key)
        if cached.present?
          next_value = cached.to_i + 1
          Rails.cache.write(cache_key, next_value, expires_in: window_seconds)
          return next_value
        end

        fallback_request_count
      end

      def cache_key
        "api:v1:rate-limit:token:#{token.id}"
      end

      def limit
        [ Rails.application.config.x.api.rate_limit_per_minute.to_i, 1 ].max
      end

      def window_seconds
        [ Rails.application.config.x.api.rate_limit_window_seconds.to_i, 1 ].max
      end

      def fallback_request_count
        self.class.mutex.synchronize do
          entry = self.class.memory_counters[cache_key]
          if entry.blank? || entry[:expires_at] <= Time.current
            entry = { count: 0, expires_at: Time.current + window_seconds }
          end

          entry[:count] += 1
          self.class.memory_counters[cache_key] = entry
          entry[:count]
        end
      end
    end
  end
end
