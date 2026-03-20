module Epistularium
  class ConnectionSyncService
    def initialize(account:, full_backfill: nil, max_messages_per_mailbox: nil, update_cursor: true)
      @account = account
      @full_backfill = full_backfill
      @max_messages_per_mailbox = max_messages_per_mailbox
      @update_cursor = update_cursor
    end

    def call
      adapter.sync!(
        full_backfill: @full_backfill,
        max_messages_per_mailbox: @max_messages_per_mailbox,
        update_cursor: @update_cursor
      )
      account.update!(status: "connected", last_synced_at: Time.current, last_error: nil)
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
  end
end
