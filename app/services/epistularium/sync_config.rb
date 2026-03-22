module Epistularium
  module SyncConfig
    BACKFILL_QUEUE = "epistularium_backfill".freeze
    BACKFILL_WINDOW_LABEL = "Last 12 months".freeze
    BOOTSTRAP_MESSAGE_LIMIT = 50
    FRESH_SYNC_INTERVAL = 10.minutes
    BACKFILL_SYNC_INTERVAL = 60.minutes
    FOLLOW_UP_DELAY = 2.seconds
    IMAP_FULL_BACKFILL_BATCH_SIZE = 50
    BACKFILL_LOOKBACK = 12.months

    module_function

    def backfill_cutoff_time(reference_time = Time.current)
      reference_time - BACKFILL_LOOKBACK
    end

    def backfill_cutoff_date(reference_time = Time.current)
      backfill_cutoff_time(reference_time).to_date
    end
  end
end
