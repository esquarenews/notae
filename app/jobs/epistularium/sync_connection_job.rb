module Epistularium
  class SyncConnectionJob < ApplicationJob
    queue_as :default

    AUTH_FAILURE_AUTO_DISABLE_MESSAGE = "Auto-disabled after authentication failure. Update credentials and re-enable account.".freeze
    LOCK_TTL = 10.minutes
    BOOTSTRAP_MESSAGE_LIMIT = 50
    FULL_BACKFILL_MESSAGE_LIMIT = 200
    FOLLOW_UP_DELAY = 2.seconds

    def perform(account_id, mode: nil)
      account = EpistulariumAccount.find_by(id: account_id)
      return if account.blank?
      return unless acquire_sync_lock(account.id)

      result = Epistularium::ConnectionSyncService.new(account: account, **sync_options_for(account: account, mode: mode)).call
      enqueue_follow_up_sync(account: account, mode: mode, result: result)
    rescue StandardError => error
      raise unless permanent_auth_failure?(error)

      account.update!(
        enabled: false,
        status: "sync_error",
        last_error: "#{error.message} #{AUTH_FAILURE_AUTO_DISABLE_MESSAGE}"
      )
      Rails.logger.warn("Epistularium sync auto-disabled account=#{account.id} provider=#{account.provider}: #{error.class}: #{error.message}")
    ensure
      release_sync_lock(account_id)
    end

    private

    def sync_options_for(account:, mode:)
      case mode.to_s
      when "bootstrap"
        bootstrap_sync_options_for(account)
      when "full_backfill"
        full_backfill_sync_options_for(account)
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
        self.class.set(wait: FOLLOW_UP_DELAY).perform_later(account.id, mode: "full_backfill")
      elsif %w[imap amazon_workmail].include?(account.provider) && result.is_a?(Hash) && result[:backfill_remaining]
        self.class.set(wait: FOLLOW_UP_DELAY).perform_later(account.id, mode: "full_backfill")
      end
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

    def acquire_sync_lock(account_id)
      Rails.cache.write(sync_lock_key(account_id), true, unless_exist: true, expires_in: LOCK_TTL)
    rescue NotImplementedError
      return false if Rails.cache.read(sync_lock_key(account_id)).present?

      Rails.cache.write(sync_lock_key(account_id), true, expires_in: LOCK_TTL)
      true
    end

    def release_sync_lock(account_id)
      Rails.cache.delete(sync_lock_key(account_id))
    rescue StandardError
      nil
    end

    def sync_lock_key(account_id)
      "epistularium:sync_connection:#{account_id}"
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
  end
end
