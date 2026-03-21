module Epistularium
  class SyncConnectionJob < ApplicationJob
    queue_as :default

    AUTH_FAILURE_AUTO_DISABLE_MESSAGE = "Auto-disabled after authentication failure. Update credentials and re-enable account.".freeze
    AUTO_SYNC_INTERVAL = 10.minutes
    STALE_SYNC_AFTER = 20.minutes
    BOOTSTRAP_MESSAGE_LIMIT = 50
    FULL_BACKFILL_MESSAGE_LIMIT = 200
    FOLLOW_UP_DELAY = 2.seconds

    def perform(account_id, mode: nil)
      claimed = false
      account = EpistulariumAccount.find_by(id: account_id)
      return if account.blank?
      claimed = claim_sync!(account)
      return unless claimed

      result = Epistularium::ConnectionSyncService.new(account: account, **sync_options_for(account: account, mode: mode)).call
      enqueue_follow_up_sync(account: account, mode: mode, result: result)
      enqueue_recurring_sync(account)
    rescue StandardError => error
      raise unless permanent_auth_failure?(error)

      account.update!(
        enabled: false,
        status: "sync_error",
        last_error: "#{error.message} #{AUTH_FAILURE_AUTO_DISABLE_MESSAGE}"
      )
      Rails.logger.warn("Epistularium sync auto-disabled account=#{account.id} provider=#{account.provider}: #{error.class}: #{error.message}")
    ensure
      release_sync_state(account_id) if claimed
    end

    private

    def sync_options_for(account:, mode:)
      case mode.to_s
      when "bootstrap"
        bootstrap_sync_options_for(account)
      when "full_backfill"
        full_backfill_sync_options_for(account)
      when "incremental"
        incremental_sync_options_for(account)
      else
        return {
          full_backfill: true,
          max_messages_per_mailbox: FULL_BACKFILL_MESSAGE_LIMIT,
          update_cursor: true
        } if batched_imap_backfill_required?(account)

        {}
      end
    end

    def enqueue_follow_up_sync(account:, mode:, result:)
      if mode.to_s == "bootstrap"
        Epistularium::SyncEnqueueService.new(
          account: account,
          mode: "full_backfill",
          wait: FOLLOW_UP_DELAY,
          throttle: 0,
          allow_while_syncing: true
        ).call
      elsif mode.to_s == "incremental" && account.full_backfill_pending?
        Epistularium::SyncEnqueueService.new(
          account: account,
          mode: "full_backfill",
          wait: FOLLOW_UP_DELAY,
          throttle: 0,
          allow_while_syncing: true
        ).call
      elsif %w[imap amazon_workmail].include?(account.provider) && result.is_a?(Hash) && result[:backfill_remaining]
        Epistularium::SyncEnqueueService.new(
          account: account,
          mode: "full_backfill",
          wait: FOLLOW_UP_DELAY,
          throttle: 0,
          allow_while_syncing: true
        ).call
      end
    end

    def enqueue_recurring_sync(account)
      return unless account.enabled?

      Epistularium::SyncEnqueueService.new(
        account: account,
        mode: Epistularium::SyncEnqueueService.preferred_mode_for(account, prioritize_fresh: true),
        wait: AUTO_SYNC_INTERVAL,
        throttle: AUTO_SYNC_INTERVAL,
        allow_while_syncing: true
      ).call
    end

    def batched_imap_backfill_required?(account)
      %w[imap amazon_workmail].include?(account.provider) &&
        account.settings_json.to_h["full_backfill_completed_at"].blank?
    end

    def permanent_auth_failure?(error)
      message = error.message.to_s.downcase
      return false if message.blank?

      message.include?("imap authentication failed") ||
        message.include?("gmail authentication failed") ||
        message.include?("token refresh failed") ||
        message.include?("invalid_client") ||
        message.include?("invalid credentials") ||
        message.include?("access denied")
    end

    def claim_sync!(account)
      claimed = false

      account.with_lock do
        account.reload
        account.clear_stale_sync_state!(stale_after: STALE_SYNC_AFTER)
        next if account.sync_active?(stale_after: STALE_SYNC_AFTER)

        account.mark_sync_started!
        account.clear_sync_enqueued!
        claimed = true
      end

      claimed
    end

    def release_sync_state(account_id)
      account = EpistulariumAccount.find_by(id: account_id)
      return if account.blank?

      account.clear_sync_started!
    end

    def bootstrap_sync_options_for(account)
      if account.provider == "gmail"
        {
          full_backfill: false,
          max_messages_per_mailbox: BOOTSTRAP_MESSAGE_LIMIT,
          update_cursor: true
        }
      else
        {
          full_backfill: false,
          max_messages_per_mailbox: BOOTSTRAP_MESSAGE_LIMIT,
          update_cursor: false
        }
      end
    end

    def full_backfill_sync_options_for(account)
      if account.provider == "gmail"
        {
          full_backfill: true,
          update_cursor: true
        }
      else
        {
          full_backfill: true,
          max_messages_per_mailbox: FULL_BACKFILL_MESSAGE_LIMIT,
          update_cursor: true
        }
      end
    end

    def incremental_sync_options_for(account)
      {
        full_backfill: false,
        max_messages_per_mailbox: BOOTSTRAP_MESSAGE_LIMIT,
        update_cursor: true
      }.tap do |options|
        options[:update_cursor] = true if account.provider == "gmail"
      end
    end
  end
end
