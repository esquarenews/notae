require "cgi"
require "json"
require "net/http"
require "time"
require "uri"

module Epistularium
  module Providers
    class GmailAdapter < BaseAdapter
      GMAIL_API_BASE_URL = "https://gmail.googleapis.com".freeze
      TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")
      REQUEST_TIMEOUT_SECONDS = 30
      REQUEST_OPEN_TIMEOUT_SECONDS = 10
      MAILBOX_LABELS = {
        "inbox" => "INBOX",
        "sent" => "SENT"
      }.freeze

      def sync!(full_backfill: nil, max_messages_per_mailbox: nil, update_cursor: true)
        ensure_credentials!
        latest_synced_at = parsed_sync_cursor
        use_full_backfill = full_backfill.nil? ? full_backfill_required? : full_backfill

        MAILBOX_LABELS.each do |mailbox, label_id|
          sync_mailbox!(
            mailbox: mailbox,
            label_id: label_id,
            full_backfill: use_full_backfill,
            max_messages_per_mailbox: max_messages_per_mailbox
          ) do |message_time|
            latest_synced_at = [ latest_synced_at, message_time ].compact.max
          end
        end

        account.sync_cursor = latest_synced_at&.iso8601 if update_cursor
        settings = account.settings_json.to_h
        settings["full_backfill_completed_at"] ||= Time.current.iso8601 if use_full_backfill && update_cursor
        account.settings_json = settings
        account.save!
        true
      end

      private

      def sync_mailbox!(mailbox:, label_id:, full_backfill:, max_messages_per_mailbox:)
        remaining = max_messages_per_mailbox.to_i.positive? ? max_messages_per_mailbox.to_i : nil
        page_token = nil
        loop do
          response = fetch_json(
            path: "/gmail/v1/users/me/messages",
            params: {
              labelIds: label_id,
              maxResults: 100,
              q: gmail_query(full_backfill: full_backfill),
              pageToken: page_token.presence,
              includeSpamTrash: false
            }.compact
          )

          message_refs = Array(response["messages"])
          message_refs = message_refs.first(remaining) if remaining.present?

          message_refs.each do |message_ref|
            remote_message = fetch_json(
              path: "/gmail/v1/users/me/messages/#{CGI.escape(message_ref.fetch('id').to_s)}",
              params: { format: "full" }
            )
            message_time = upsert_remote_message!(mailbox: mailbox, remote_message: remote_message)
            yield(message_time) if block_given? && message_time.present?
            remaining -= 1 if remaining.present?
          end

          break if remaining == 0

          page_token = response["nextPageToken"].to_s.presence
          break if page_token.blank?
        end
      end

      def upsert_remote_message!(mailbox:, remote_message:)
        payload = remote_message["payload"].is_a?(Hash) ? remote_message["payload"] : {}
        headers = Array(payload["headers"]).each_with_object({}) do |header, hash|
          next unless header.is_a?(Hash)

          name = header["name"].to_s
          value = header["value"].to_s
          hash[name] = value if name.present? && value.present?
        end
        text_parts, html_parts, attachments = extract_gmail_parts(payload)
        body_text, body_html = self.class.normalize_email_bodies(
          text_content: text_parts.reject(&:blank?).join("\n\n"),
          html_content: html_parts.reject(&:blank?).join("\n\n")
        )
        internal_time = Time.at(remote_message["internalDate"].to_i / 1000.0).utc if remote_message["internalDate"].present?

        attributes = build_message_attributes_from_mail(
          mail: Mail.new,
          mailbox: mailbox,
          provider_message_id: remote_message["id"].to_s,
          provider_thread_id: remote_message["threadId"].to_s,
          unread: Array(remote_message["labelIds"]).include?("UNREAD"),
          received_at: internal_time,
          snippet: remote_message["snippet"].to_s,
          metadata: {
            "provider" => "gmail",
            "label_ids" => Array(remote_message["labelIds"]),
            "history_id" => remote_message["historyId"].to_s.presence
          },
          header_overrides: headers
        )
        attributes[:body_text] = body_text.presence
        attributes[:body_html] = body_html.presence
        attributes[:attachment_metadata_json] = attachments

        upsert_message!(attributes)
        internal_time || attributes[:received_at]
      end

      def extract_gmail_parts(payload, text_parts = [], html_parts = [], attachments = [])
        mime_type = payload["mimeType"].to_s.downcase
        body = payload["body"].is_a?(Hash) ? payload["body"] : {}

        if payload["filename"].to_s.present?
          attachments << {
            "filename" => payload["filename"].to_s,
            "mime_type" => mime_type.presence,
            "size" => body["size"].to_i.positive? ? body["size"].to_i : nil,
            "attachment_id" => body["attachmentId"].to_s.presence
          }.compact
        elsif mime_type.start_with?("text/plain")
          text_parts << decode_base64url(body["data"])
        elsif mime_type.start_with?("text/html")
          html_parts << decode_base64url(body["data"])
        end

        Array(payload["parts"]).each do |part|
          extract_gmail_parts(part, text_parts, html_parts, attachments)
        end

        [ text_parts, html_parts, attachments ]
      end

      def gmail_query(full_backfill:)
        return "after:#{Epistularium::SyncConfig.backfill_cutoff_time.to_i}" if full_backfill
        return nil if parsed_sync_cursor.blank?

        "after:#{(parsed_sync_cursor - 5.minutes).to_i}"
      end

      def full_backfill_required?
        account.settings_json.to_h["full_backfill_completed_at"].blank?
      end

      def parsed_sync_cursor
        value = account.sync_cursor.to_s.strip
        return nil if value.blank?

        Time.iso8601(value)
      rescue ArgumentError
        nil
      end

      def ensure_credentials!
        return if account.google_tokens_configured? && account.access_token.present?
        return refresh_access_token! if account.google_tokens_configured? && account.refresh_token.present?

        raise "Gmail authentication failed. Re-authorize Google OAuth."
      end

      def fetch_json(path:, params: {}, allow_refresh: true)
        uri = URI.join(GMAIL_API_BASE_URL, path)
        compact_params = params.compact
        uri.query = URI.encode_www_form(compact_params) if compact_params.any?
        response = perform_request(uri: uri, access_token: account.access_token)
        return parse_json(response.body) if response.is_a?(Net::HTTPSuccess)

        if allow_refresh && response.code.to_i == 401 && account.refresh_token.present?
          refresh_access_token!
          return fetch_json(path: path, params: params, allow_refresh: false)
        end

        raise "Gmail request failed (#{response.code}): #{extract_error_message(parse_json(response.body))}"
      end

      def perform_request(uri:, access_token:)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: true,
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      end

      def refresh_access_token!
        credential_candidates = refresh_token_credential_candidates
        raise "Google token refresh failed (401): OAuth client was not found" if credential_candidates.empty?

        last_error_message = nil
        credential_candidates.each do |candidate|
          response = perform_token_refresh_request(
            client_id: candidate.fetch(:client_id),
            client_secret: candidate.fetch(:client_secret)
          )
          status = response.code.to_i
          body = parse_json(response.body)
          access_token = body["access_token"].to_s.strip

          if (200..299).cover?(status) && access_token.present?
            persist_refreshed_tokens!(body)
            persist_oauth_client_credentials!(
              client_id: candidate.fetch(:client_id),
              client_secret: candidate.fetch(:client_secret)
            )
            return
          end

          message = extract_error_message(body)
          last_error_message = "Google token refresh failed (#{status}): #{message}"
          next if invalid_client_error?(status: status, message: message)

          raise last_error_message
        end

        raise(last_error_message || "Google token refresh failed.")
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google token refresh failed (401): #{error.message}"
      end

      def perform_token_refresh_request(client_id:, client_secret:)
        request = Net::HTTP::Post.new(TOKEN_ENDPOINT)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: account.refresh_token,
          grant_type: "refresh_token"
        )

        Net::HTTP.start(
          TOKEN_ENDPOINT.host,
          TOKEN_ENDPOINT.port,
          use_ssl: true,
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      end

      def refresh_token_credential_candidates
        candidates = []
        if account.oauth_client_id.present? && account.oauth_client_secret.present?
          candidates << {
            client_id: account.oauth_client_id.to_s.strip,
            client_secret: account.oauth_client_secret.to_s.strip
          }
        end

        fallback_client_id = Epistularium::GoogleOauthService.resolved_client_id.to_s.strip.presence
        fallback_client_secret = Epistularium::GoogleOauthService.resolved_client_secret.to_s.strip.presence
        if fallback_client_id.present? && fallback_client_secret.present?
          candidates << { client_id: fallback_client_id, client_secret: fallback_client_secret }
        end

        candidates.uniq
      end

      def invalid_client_error?(status:, message:)
        return false unless [ 400, 401 ].include?(status)

        lowered = message.to_s.downcase
        lowered.include?("invalid_client") || lowered.include?("oauth client was not found")
      end

      def persist_refreshed_tokens!(token_body)
        account.access_token = token_body["access_token"].to_s.strip.presence
        refreshed_token = token_body["refresh_token"].to_s.strip
        account.refresh_token = refreshed_token if refreshed_token.present?

        settings = account.settings_json.to_h
        settings["google_access_token_expires_at"] =
          if token_body["expires_in"].to_i.positive?
            (Time.current + token_body["expires_in"].to_i.seconds).iso8601
          else
            nil
          end
        account.settings_json = settings.compact
        account.save!
      end

      def persist_oauth_client_credentials!(client_id:, client_secret:)
        return if client_id.blank? || client_secret.blank?
        return if account.oauth_client_id == client_id && account.oauth_client_secret == client_secret

        account.update!(
          oauth_client_id: client_id,
          oauth_client_secret: client_secret
        )
      end

      def parse_json(raw_body)
        body = raw_body.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      def extract_error_message(body)
        error_value = body["error"]
        nested_error_message = error_value.is_a?(Hash) ? error_value["message"].to_s.presence : nil

        body["error_description"].to_s.presence ||
          nested_error_message ||
          error_value.to_s.presence ||
          "Unknown Gmail API error"
      end
    end
  end
end
