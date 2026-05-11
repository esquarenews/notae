# frozen_string_literal: true

require "digest"

module Notae
  module RequestRateLimiter
    module_function

    def consume!(name:, discriminator:, limit:, period:)
      key = cache_key(name, discriminator)
      count = cache_store.increment(key, 1, expires_in: period)

      unless count
        cache_store.write(key, 1, expires_in: period)
        count = 1
      end

      count <= limit
    end

    def reset!
      memory_store.clear
    end

    def cache_key(name, discriminator)
      digest = Digest::SHA256.hexdigest(discriminator.to_s)
      "notae:rate-limit:#{name}:#{digest}"
    end

    def cache_store
      return memory_store if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

      Rails.cache
    end

    def memory_store
      @memory_store ||= ActiveSupport::Cache::MemoryStore.new
    end
  end
end
