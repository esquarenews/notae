module Epistularium
  class ConnectionSyncService
    def initialize(account:, full_backfill: nil, max_messages_per_mailbox: nil, update_cursor: true)
      @account = account
      @full_backfill = full_backfill
      @max_messages_per_mailbox = max_messages_per_mailbox
      @update_cursor = update_cursor
    end

    def call
      result = adapter.sync!(
        full_backfill: @full_backfill,
        max_messages_per_mailbox: @max_messages_per_mailbox,
        update_cursor: @update_cursor
      )
      timestamp = Time.current
      settings = account.settings_json.to_h.deep_dup
      settings[sync_timestamp_key] = timestamp.iso8601
      account.update!(
        status: "connected",
        last_synced_at: timestamp,
        last_error: nil,
        settings_json: settings
      )
      result
    rescue StandardError => error
      account.update!(status: "sync_error", last_error: error.message)
      raise
    end

    private

    attr_reader :account

    def adapter
      @adapter ||= case account.provider
      when "gmail"
        Epistularium::Providers::GmailAdapter.new(account: account)
      when "amazon_workmail"
        Epistularium::Providers::AmazonWorkmailAdapter.new(account: account)
      when "imap"
        Epistularium::Providers::ImapAdapter.new(account: account)
      else
        Epistularium::Providers::BaseAdapter.new(account: account)
      end
    end

    def sync_timestamp_key
      resolved_full_backfill? ? "last_backfill_sync_at" : "last_fresh_sync_at"
    end

    def resolved_full_backfill?
      return @full_backfill unless @full_backfill.nil?

      account.full_backfill_pending?
    end
  end
end
