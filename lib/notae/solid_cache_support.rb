module Notae
  module SolidCacheSupport
    module_function

    def session_store
      use_solid_cache? ? :cache_store : :cookie_store
    end

    def cache_store
      use_solid_cache? ? :solid_cache_store : :memory_store
    end

    def use_solid_cache?
      return false if Rails.env.test?
      return false unless solid_cache_requested?

      solid_cache_table_available?
    end

    def solid_cache_requested?
      raw_value = ENV["NOTAE_SOLID_CACHE"]
      return true if raw_value.nil?

      ActiveModel::Type::Boolean.new.cast(raw_value)
    end

    def solid_cache_table_available?
      ActiveRecord::Base.connection.data_source_exists?("solid_cache_entries")
    rescue StandardError
      false
    end
  end
end
