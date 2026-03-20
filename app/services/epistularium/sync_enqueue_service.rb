module Epistularium
  class SyncEnqueueService
    DEFAULT_THROTTLE = 1.minute

    def self.preferred_mode_for(account)
      return nil if account.blank?
      return nil unless %w[gmail imap amazon_workmail].include?(account.provider)
      return "bootstrap" if account.last_synced_at.blank?
      return "bootstrap" unless account.epistularium_messages.exists?

      nil
    end

    def initialize(account:, mode: nil, throttle: DEFAULT_THROTTLE)
      @account = account
      @mode = mode.presence
      @throttle = throttle
    end

    def call
      return false if throttled? && recently_enqueued?

      mark_enqueued! if throttled?
      enqueue_job!
      true
    rescue StandardError
      clear_mark!
      raise
    end

    private

    attr_reader :account, :mode, :throttle

    def enqueue_job!
      if mode.present?
        Epistularium::SyncConnectionJob.perform_later(account.id, mode: mode)
      else
        Epistularium::SyncConnectionJob.perform_later(account.id)
      end
    end

    def throttled?
      throttle.to_i.positive?
    end

    def recently_enqueued?
      Rails.cache.read(cache_key).present?
    rescue StandardError
      false
    end

    def mark_enqueued!
      Rails.cache.write(cache_key, true, expires_in: throttle)
    rescue StandardError
      nil
    end

    def clear_mark!
      Rails.cache.delete(cache_key)
    rescue StandardError
      nil
    end

    def cache_key
      "epistularium:sync-enqueue:#{account.id}"
    end
  end
end
