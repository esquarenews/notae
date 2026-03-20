module Epistularium
  class SyncEnqueueService
    DEFAULT_THROTTLE = 1.minute
    ENQUEUE_RESULTS = {
      enqueued: :enqueued,
      already_running: :already_running,
      already_queued: :already_queued
    }.freeze

    def self.preferred_mode_for(account)
      return nil if account.blank?
      return nil unless %w[gmail imap amazon_workmail].include?(account.provider)
      return "bootstrap" if account.last_synced_at.blank?
      return "bootstrap" unless account.epistularium_messages.exists?

      nil
    end

    def initialize(account:, mode: nil, throttle: DEFAULT_THROTTLE, wait: nil, allow_while_syncing: false)
      @account = account
      @mode = mode.presence
      @throttle = throttle
      @wait = wait
      @allow_while_syncing = allow_while_syncing
    end

    def call
      result = nil

      account.with_lock do
        account.reload
        account.clear_stale_sync_state!

        result =
          if !allow_while_syncing && account.sync_active?
            ENQUEUE_RESULTS[:already_running]
          elsif throttled? && recently_enqueued?
            ENQUEUE_RESULTS[:already_queued]
          else
            mark_enqueued!
            ENQUEUE_RESULTS[:enqueued]
          end
      end

      enqueue_job! if result == ENQUEUE_RESULTS[:enqueued]
      result
    rescue StandardError
      clear_mark!
      raise
    end

    private

    attr_reader :account, :mode, :throttle, :wait, :allow_while_syncing

    def enqueue_job!
      job = wait.present? ? Epistularium::SyncConnectionJob.set(wait: wait) : Epistularium::SyncConnectionJob

      if mode.present?
        job.perform_later(account.id, mode: mode)
      else
        job.perform_later(account.id)
      end
    end

    def throttled?
      throttle.to_i.positive?
    end

    def recently_enqueued?
      account.sync_recently_enqueued?(within: throttle)
    end

    def mark_enqueued!
      account.mark_sync_enqueued!
    end

    def clear_mark!
      account.clear_sync_enqueued!
    end
  end
end
