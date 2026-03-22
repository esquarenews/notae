module Epistularium
  class DueSyncScheduler
    FRESH_STALE_AFTER = Epistularium::SyncConfig::FRESH_SYNC_INTERVAL
    ENQUEUE_STALE_AFTER = 2.minutes

    def initialize(accounts:)
      @accounts = Array(accounts)
    end

    def call
      accounts.each do |account|
        queue_due_sync_for(account)
      rescue StandardError => error
        Rails.logger.warn("Failed to queue Epistularium due sync for #{account.id}: #{error.class}: #{error.message}")
      end
    end

    private

    attr_reader :accounts

    def queue_due_sync_for(account)
      return unless account.enabled?

      account.clear_stale_sync_state!
      return if account.sync_active?

      if account.sync_queue_stalled?(stale_after: ENQUEUE_STALE_AFTER)
        account.clear_sync_enqueued!
      elsif account.sync_enqueued_at.present?
        return
      end

      if account.fresh_sync_due?(interval: FRESH_STALE_AFTER)
        enqueue_mode(account, Epistularium::SyncEnqueueService.fresh_mode_for(account))
      elsif account.backfill_sync_due?
        enqueue_mode(account, Epistularium::SyncEnqueueService.backfill_mode_for(account))
      end
    end

    def enqueue_mode(account, mode)
      return if mode.blank?

      Epistularium::SyncEnqueueService.new(
        account: account,
        mode: mode,
        throttle: 0
      ).call
    end
  end
end
