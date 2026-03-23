require "mail"
require "net/imap"

module Epistularium
  module Providers
    class ImapAdapter < BaseAdapter
      DEFAULT_SENT_MAILBOX = "Sent".freeze
      DEFAULT_FULL_BACKFILL_BATCH_SIZE = Epistularium::SyncConfig::IMAP_FULL_BACKFILL_BATCH_SIZE

      def sync!(full_backfill: nil, max_messages_per_mailbox: nil, update_cursor: true)
        use_full_backfill = full_backfill.nil? ? full_backfill_required? : full_backfill
        latest_synced_at = parsed_sync_cursor
        settings = account.settings_json.to_h
        backfill_remaining = false

        with_imap do |imap|
          mailboxes_to_sync.each do |mailbox, remote_mailbox|
            next unless mailbox_exists?(imap, remote_mailbox)

            imap.select(remote_mailbox)
            uids, mailbox_backfill_remaining = selected_uids_for_mailbox(
              imap: imap,
              mailbox: mailbox,
              full_backfill: use_full_backfill,
              max_messages_per_mailbox: max_messages_per_mailbox,
              settings: settings
            )
            backfill_remaining ||= mailbox_backfill_remaining
            Array(uids).each do |uid|
              data = imap.uid_fetch(uid, [ "BODY.PEEK[]", "FLAGS", "INTERNALDATE" ])&.first
              next if data.blank?

              attributes = data.attr
              raw_message = attributes["BODY[]"].presence || attributes["RFC822"].to_s
              next if raw_message.blank?

              mail = Mail.read_from_string(raw_message)
              internal_time = attributes["INTERNALDATE"]&.to_time&.utc
              message = upsert_message!(
                build_message_attributes_from_mail(
                  mail: mail,
                  mailbox: mailbox,
                  provider_message_id: "#{mailbox}:#{uid}",
                  unread: !Array(attributes["FLAGS"]).map(&:to_s).include?("\\Seen"),
                  received_at: internal_time,
                  metadata: {
                    "provider" => account.provider,
                    "remote_mailbox" => remote_mailbox,
                    "uid" => uid
                  }
                )
              )
              latest_synced_at = [ latest_synced_at, message.primary_timestamp ].compact.max
            end
          end
        end

        account.sync_cursor = latest_synced_at&.iso8601 if update_cursor
        if use_full_backfill && update_cursor
          if backfill_remaining
            settings.delete("full_backfill_completed_at")
          else
            settings["full_backfill_completed_at"] ||= Time.current.iso8601
            clear_backfill_state!(settings)
          end
        end
        account.settings_json = settings
        account.save!
        { backfill_remaining: use_full_backfill && backfill_remaining }
      rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError => error
        if smtp_endpoint_error?(error.message)
          raise smtp_endpoint_error_message
        end

        if access_denied_error?(error.message)
          raise access_denied_error_message
        end

        if error.message.to_s.downcase.include?("auth") || error.message.to_s.downcase.include?("login")
          raise "IMAP authentication failed: #{error.message}"
        end

        raise
      end

      private

      def with_imap
        imap = Net::IMAP.new(account.imap_host, port: account.imap_port, ssl: account.imap_ssl?)
        imap.login(account.provider_username.to_s, account.provider_password.to_s)
        yield imap
      ensure
        begin
          imap&.logout
          imap&.disconnect
        rescue StandardError
          nil
        end
      end

      def mailboxes_to_sync
        [
          [ "inbox", "INBOX" ],
          [ "sent", account.sent_mailbox_name.presence || DEFAULT_SENT_MAILBOX ]
        ]
      end

      def mailbox_exists?(imap, remote_mailbox)
        imap.list("", remote_mailbox).present?
      rescue Net::IMAP::NoResponseError, Net::IMAP::BadResponseError
        false
      end

      def selected_uids_for_mailbox(imap:, mailbox:, full_backfill:, max_messages_per_mailbox:, settings:)
        if full_backfill
          full_backfill_uids_for_mailbox(
            imap: imap,
            mailbox: mailbox,
            max_messages_per_mailbox: max_messages_per_mailbox,
            settings: settings
          )
        else
          uids = Array(imap.uid_search(search_query(full_backfill: false))).map(&:to_i).sort
          uids = uids.last(max_messages_per_mailbox.to_i) if max_messages_per_mailbox.to_i.positive?
          [ uids, false ]
        end
      end

      def full_backfill_uids_for_mailbox(imap:, mailbox:, max_messages_per_mailbox:, settings:)
        uids = Array(imap.uid_search(search_query(full_backfill: true))).map(&:to_i).sort
        before_uid = settings[backfill_before_uid_key(mailbox)].to_i
        eligible_uids = before_uid.positive? ? uids.take_while { |uid| uid < before_uid } : uids
        batch_limit = max_messages_per_mailbox.to_i.positive? ? max_messages_per_mailbox.to_i : DEFAULT_FULL_BACKFILL_BATCH_SIZE
        selected_uids = eligible_uids.last(batch_limit)
        remaining = eligible_uids.length > selected_uids.length

        if remaining && selected_uids.any?
          settings[backfill_before_uid_key(mailbox)] = selected_uids.first
        else
          settings.delete(backfill_before_uid_key(mailbox))
        end

        [ selected_uids, remaining ]
      end

      def search_query(full_backfill:)
        if full_backfill
          return [ "SINCE", Epistularium::SyncConfig.backfill_cutoff_date.strftime("%d-%b-%Y") ]
        end

        return [ "ALL" ] if parsed_sync_cursor.blank?

        [ "SINCE", (parsed_sync_cursor.to_date - 1.day).strftime("%d-%b-%Y") ]
      end

      def full_backfill_required?
        account.settings_json.to_h["full_backfill_completed_at"].blank?
      end

      def clear_backfill_state!(settings)
        mailboxes_to_sync.each do |mailbox, _remote_mailbox|
          settings.delete(backfill_before_uid_key(mailbox))
        end
      end

      def backfill_before_uid_key(mailbox)
        "imap_backfill_before_uid_#{mailbox}"
      end

      def smtp_endpoint_error?(message)
        value = message.to_s.downcase
        value.include?('bad response type "smtp') || value.include?("esmtp")
      end

      def smtp_endpoint_error_message
        if account.provider == "amazon_workmail"
          "Amazon WorkMail IMAP host is pointing at SMTP. Use the incoming IMAP endpoint, for example imap.mail.<region>.awsapps.com on port 993."
        else
          "IMAP host appears to be an SMTP server. Use the incoming IMAP endpoint on port 993."
        end
      end

      def access_denied_error?(message)
        value = message.to_s.downcase
        value.include?("access denied")
      end

      def access_denied_error_message
        if account.provider == "amazon_workmail"
          "Amazon WorkMail denied the IMAP login. Use the full mailbox email address as the username, verify the password or personal access token, and confirm IMAP is allowed by the organization's access control rules."
        else
          "IMAP login was denied by the mail server. Verify the username and password for the incoming mail account."
        end
      end

      def parsed_sync_cursor
        value = account.sync_cursor.to_s.strip
        return nil if value.blank?

        Time.iso8601(value)
      rescue ArgumentError
        nil
      end
    end
  end
end
