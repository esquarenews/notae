module Queueing
  module JobEnqueueSafety
    QUEUE_ERROR_CLASS_NAMES = [
      "RedisClient::CannotConnectError",
      "Redis::CannotConnectError",
      "Gem::LoadError",
      "Sidekiq::Shutdown"
    ].freeze

    def self.queue_unavailable?(error)
      error_chain(error).any? do |candidate|
        candidate.is_a?(Errno::ECONNREFUSED) ||
          QUEUE_ERROR_CLASS_NAMES.include?(candidate.class.name) ||
          candidate.message.to_s.include?("Connection refused - connect(2) for 127.0.0.1:6379")
      end
    end

    def self.error_chain(error)
      chain = []
      current = error

      while current.present?
        chain << current
        current = current.cause
      end

      chain
    end
  end
end
