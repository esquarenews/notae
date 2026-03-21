module Epistularium
  class SyncRecoveryService
    STALLED_ENQUEUE_AFTER = 2.minutes

    def initialize(account:, mode: nil)
      @account = account
      @mode = mode.presence
    end

    def call
      return false unless recoverable?

      Epistularium::SyncConnectionJob.perform_now(account.id, mode: recovery_mode)
      true
    end

    private

    attr_reader :account, :mode

    def recoverable?
      account.present? &&
        account.enabled? &&
        due_for_sync? &&
        account.sync_queue_stalled?(stale_after: STALLED_ENQUEUE_AFTER)
    end

    def due_for_sync?
      account.last_synced_at.blank? || account.last_synced_at <= Epistularium::DueSyncScheduler::STALE_AFTER.ago
    end

    def recovery_mode
      mode || default_recovery_mode
    end

    def default_recovery_mode
      return "bootstrap" if account.last_synced_at.blank?
      return "bootstrap" unless account.epistularium_messages.exists?

      "incremental"
    end
  end
end
