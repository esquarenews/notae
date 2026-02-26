module Search
  class AiRateLimiter
    OPERATIONS = %w[semantic_search answer_generation].freeze

    class << self
      def memory_counters
        @memory_counters ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end

      def allowed?(user:, workspace:, operation:)
        new(user: user, workspace: workspace, operation: operation).allowed?
      end
    end

    def initialize(user:, workspace:, operation:)
      @user = user
      @workspace = workspace
      @operation = operation.to_s
    end

    def allowed?
      return false unless valid_operation?

      request_count <= limit
    end

    private

    attr_reader :user, :workspace, :operation

    def valid_operation?
      OPERATIONS.include?(operation)
    end

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

    def cache_key
      "search:ai-rate-limit:user:#{user.id}:workspace:#{workspace.id}:operation:#{operation}"
    end

    def limit
      if operation == "answer_generation"
        [ user.resolved_ai_search_answer_rate_limit_per_minute, 1 ].max
      else
        [ user.resolved_ai_search_semantic_rate_limit_per_minute, 1 ].max
      end
    end

    def window_seconds
      [ Rails.application.config.x.ai_search.rate_limit_window_seconds.to_i, 1 ].max
    end
  end
end
