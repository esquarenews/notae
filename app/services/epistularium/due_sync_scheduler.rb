module Epistularium
  class DueSyncScheduler
    STALE_AFTER = 10.minutes
    ENQUEUE_THROTTLE = 5.minutes

    def initialize(accounts:)
      @accounts = Array(accounts)
    end

    def call
      accounts.each do |account|
        next unless account.enabled?
        next unless due_for_sync?(account)

        Epistularium::SyncEnqueueService.new(
          account: account,
          mode: Epistularium::SyncEnqueueService.preferred_mode_for(account),
          throttle: ENQUEUE_THROTTLE
        ).call
      rescue StandardError => error
        Rails.logger.warn("Failed to queue Epistularium due sync for #{account.id}: #{error.class}: #{error.message}")
      end
    end

    private

    attr_reader :accounts

    def due_for_sync?(account)
      account.last_synced_at.blank? || account.last_synced_at <= STALE_AFTER.ago
    end
  end
end
