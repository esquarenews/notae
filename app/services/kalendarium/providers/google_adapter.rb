require "cgi"
require "digest"
require "json"
require "net/http"
require "time"
require "uri"

module Kalendarium
  module Providers
    class GoogleAdapter < BaseAdapter
      def sync!(calendar: nil)
        ensure_credentials!

        if calendar.present?
          ensure_calendar_belongs_to_connection!(calendar)
          sync_single_calendar(calendar)
        else
          sync_all_calendars
        end

        true
      end

      private

      GOOGLE_CALENDAR_API_BASE_URL = "https://www.googleapis.com".freeze
      GOOGLE_TOKEN_ENDPOINT = URI("https://oauth2.googleapis.com/token")
      DEFAULT_CALENDAR_COLOR = "#3B82F6".freeze
      LOOKBACK_DAYS = 365
      LOOKAHEAD_DAYS = 365
      REQUEST_TIMEOUT_SECONDS = 30
      REQUEST_OPEN_TIMEOUT_SECONDS = 10

      def sync_all_calendars
        remote_calendars = fetch_all_remote_calendars
        synced_remote_ids = remote_calendars.map do |remote_calendar|
          local_calendar = upsert_remote_calendar(remote_calendar)
          sync_single_calendar(local_calendar)
          local_calendar.remote_id
        end

        disable_missing_provider_calendars(synced_remote_ids)
      end

      def sync_single_calendar(calendar)
        seen_remote_event_ids = []
        events = fetch_calendar_events(
          calendar_id: calendar.remote_id,
          range_start: (Time.current - LOOKBACK_DAYS.days).beginning_of_day,
          range_end: (Time.current + LOOKAHEAD_DAYS.days).end_of_day
        )

        events.each_with_index do |remote_event, index|
          remote_event_id = normalize_remote_event_id(event: remote_event, starts_at_utc: nil, index: index)
          next if remote_event_id.blank?

          status = normalize_status(remote_event["status"])
          starts_at_utc, starts_all_day = parse_google_time(remote_event["start"], fallback_time_zone: calendar.time_zone)
          if starts_at_utc.blank?
            if status == "cancelled"
              mark_cancelled_remote_event(calendar: calendar, remote_event_id: remote_event_id)
              seen_remote_event_ids << remote_event_id
            end
            next
          end

          ends_at_utc, ends_all_day = parse_google_time(remote_event["end"], fallback_time_zone: calendar.time_zone)
          ends_at_utc ||= starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
          if ends_at_utc <= starts_at_utc
            ends_at_utc = starts_all_day ? starts_at_utc + 1.day : starts_at_utc + 1.hour
          end

          remote_event_id = normalize_remote_event_id(event: remote_event, starts_at_utc: starts_at_utc, index: index)
          next if remote_event_id.blank?

          seen_remote_event_ids << remote_event_id
          upsert_remote_event(
            calendar: calendar,
            remote_event_id: remote_event_id,
            remote_event: remote_event,
            starts_at_utc: starts_at_utc,
            ends_at_utc: ends_at_utc,
            all_day: starts_all_day || ends_all_day
          )
        end

        cancel_stale_provider_events(calendar: calendar, seen_remote_event_ids: seen_remote_event_ids)
      end

      def ensure_credentials!
        return if connection.access_token.present?
        return refresh_access_token! if connection.refresh_token.present?

        raise "Google access token missing"
      end

      def ensure_calendar_belongs_to_connection!(calendar)
        return if calendar.kalendarium_connection_id == connection.id && calendar.remote_id.present?

        raise "Calendar does not belong to this Google connection"
      end

      def fetch_all_remote_calendars
        items = []
        page_token = nil

        loop do
          response = fetch_json(
            path: "/calendar/v3/users/me/calendarList",
            params: {
              maxResults: 250,
              showHidden: true,
              pageToken: page_token.presence
            }
          )
          items.concat(Array(response["items"]))
          page_token = response["nextPageToken"].to_s.presence
          break if page_token.blank?
        end

        items.reject { |calendar_item| ActiveModel::Type::Boolean.new.cast(calendar_item["deleted"]) }
      end

      def fetch_calendar_events(calendar_id:, range_start:, range_end:)
        items = []
        page_token = nil

        loop do
          response = fetch_json(
            path: "/calendar/v3/calendars/#{CGI.escape(calendar_id.to_s)}/events",
            params: {
              maxResults: 2500,
              orderBy: "startTime",
              singleEvents: true,
              showDeleted: true,
              timeMin: range_start.utc.iso8601,
              timeMax: range_end.utc.iso8601,
              pageToken: page_token.presence
            }
          )
          items.concat(Array(response["items"]))
          page_token = response["nextPageToken"].to_s.presence
          break if page_token.blank?
        end

        items
      end

      def upsert_remote_calendar(remote_calendar)
        remote_id = remote_calendar["id"].to_s
        calendar = connection.kalendarium_calendars.find_or_initialize_by(remote_id: remote_id)
        calendar.workspace = connection.workspace
        calendar.provider = connection.provider
        calendar.created_by ||= connection.created_by
        calendar.name = remote_calendar["summary"].to_s.presence || "Google calendar"
        calendar.color_hex = normalize_color_hex(remote_calendar["backgroundColor"])
        calendar.time_zone = normalize_time_zone_name(remote_calendar["timeZone"]) ||
                             normalize_time_zone_name(connection.created_by&.time_zone) ||
                             "UTC"
        calendar.read_only = read_only_access_role?(remote_calendar["accessRole"])
        calendar.source_kind = "provider"
        calendar.enabled = true if calendar.new_record?
        calendar.metadata_json = calendar.metadata_json.to_h.merge(
          "description" => remote_calendar["description"].to_s.presence,
          "etag" => remote_calendar["etag"].to_s.presence,
          "access_role" => remote_calendar["accessRole"].to_s.presence,
          "primary" => ActiveModel::Type::Boolean.new.cast(remote_calendar["primary"])
        ).compact
        calendar.save!
        calendar
      end

      def disable_missing_provider_calendars(synced_remote_ids)
        scope = connection.kalendarium_calendars.where(source_kind: "provider")
        scope = synced_remote_ids.any? ? scope.where.not(remote_id: synced_remote_ids) : scope
        scope.find_each do |calendar|
          next unless calendar.enabled?

          calendar.update!(enabled: false)
        end
      end

      def upsert_remote_event(calendar:, remote_event_id:, remote_event:, starts_at_utc:, ends_at_utc:, all_day:)
        event = calendar.kalendarium_events.find_or_initialize_by(remote_event_id: remote_event_id)
        event.workspace = connection.workspace
        event.created_by ||= connection.created_by
        event.updated_by = connection.created_by
        event.source_kind = "provider"
        event.uid = remote_event["iCalUID"].to_s.presence || remote_event["id"].to_s.presence || remote_event_id
        event.etag = remote_event["etag"].to_s.presence
        event.sequence = remote_event["sequence"].to_i
        event.title = truncate_text(remote_event["summary"], limit: 200, fallback: "(Untitled event)")
        event.description = remote_event["description"].to_s.presence
        event.location = remote_event["location"].to_s.presence
        event.starts_at_utc = starts_at_utc
        event.ends_at_utc = ends_at_utc
        event.all_day = all_day
        event.rrule = Array(remote_event.dig("recurrence")).first.to_s.presence
        event.status = normalize_status(remote_event["status"])
        event.visibility = normalize_visibility(remote_event["visibility"])
        event.last_synced_at = Time.current
        event.metadata_json = event.metadata_json.to_h.merge(
          "html_link" => remote_event["htmlLink"].to_s.presence,
          "creator_email" => remote_event.dig("creator", "email").to_s.presence,
          "organizer_email" => remote_event.dig("organizer", "email").to_s.presence,
          "recurring_event_id" => remote_event["recurringEventId"].to_s.presence,
          "original_start_time" => remote_event.dig("originalStartTime", "dateTime").to_s.presence || remote_event.dig("originalStartTime", "date").to_s.presence,
          "provider" => connection.provider
        ).compact
        event.save!
      end

      def mark_cancelled_remote_event(calendar:, remote_event_id:)
        event = calendar.kalendarium_events.find_by(remote_event_id: remote_event_id)
        return if event.blank? || event.status == "cancelled"

        event.update!(
          status: "cancelled",
          updated_by: connection.created_by,
          last_synced_at: Time.current
        )
      end

      def cancel_stale_provider_events(calendar:, seen_remote_event_ids:)
        scope = calendar.kalendarium_events.where(source_kind: "provider")
        scope = seen_remote_event_ids.any? ? scope.where.not(remote_event_id: seen_remote_event_ids) : scope
        scope.find_each do |event|
          next if event.status == "cancelled"

          event.update!(
            status: "cancelled",
            updated_by: connection.created_by,
            last_synced_at: Time.current
          )
        end
      end

      def parse_google_time(entry, fallback_time_zone:)
        data = entry.to_h
        date_value = data["date"].to_s.strip
        if date_value.present?
          date = Date.iso8601(date_value)
          return [ date.beginning_of_day.utc, true ]
        end

        date_time_value = data["dateTime"].to_s.strip
        return [ nil, false ] if date_time_value.blank?

        if date_time_value.match?(/(Z|[+-]\d{2}:\d{2})\z/)
          return [ Time.iso8601(date_time_value).utc, false ]
        end

        zone = resolve_time_zone(data["timeZone"], fallback_time_zone: fallback_time_zone)
        [ zone.parse(date_time_value)&.utc, false ]
      rescue ArgumentError, TypeError
        [ nil, false ]
      end

      def resolve_time_zone(raw_time_zone, fallback_time_zone:)
        candidates = []
        time_zone = raw_time_zone.to_s.strip
        fallback = fallback_time_zone.to_s.strip
        candidates << time_zone if time_zone.present?
        candidates << fallback if fallback.present?
        candidates << "UTC"
        candidates.each do |candidate|
          zone = ActiveSupport::TimeZone[candidate]
          return zone if zone.present?
        end

        ActiveSupport::TimeZone["UTC"]
      end

      def normalize_remote_event_id(event:, starts_at_utc:, index:)
        event_id = event["id"].to_s.strip
        recurring_event_id = event["recurringEventId"].to_s.strip
        original_start = event.dig("originalStartTime", "dateTime").to_s.strip
        original_start = event.dig("originalStartTime", "date").to_s.strip if original_start.blank?
        starts_at_value = starts_at_utc&.utc&.iso8601(6).to_s

        stable_id =
          if event_id.present?
            event_id
          elsif recurring_event_id.present? && original_start.present?
            "#{recurring_event_id}::#{original_start}"
          elsif recurring_event_id.present? && starts_at_value.present?
            "#{recurring_event_id}::#{starts_at_value}"
          elsif starts_at_value.present?
            "google-event-#{starts_at_value}"
          else
            "google-event-#{index}"
          end

        stable_id.length > 240 ? Digest::SHA256.hexdigest(stable_id) : stable_id
      end

      def fetch_json(path:, params:, allow_refresh: true)
        uri = build_api_uri(path: path, params: params)
        response = perform_api_get(uri: uri, access_token: connection.access_token)
        status = response.code.to_i
        body = parse_json(response.body)
        return body if (200..299).cover?(status)

        if [ 401, 403 ].include?(status)
          if allow_refresh && connection.refresh_token.present?
            refresh_access_token!
            return fetch_json(path: path, params: params, allow_refresh: false)
          end

          raise "Google authentication failed (#{status}). Provide a fresh access token or reconnect Google."
        end

        message = extract_api_error_message(body)
        raise "Google Calendar request failed (#{status}): #{message}"
      end

      def build_api_uri(path:, params:)
        uri = URI.join(GOOGLE_CALENDAR_API_BASE_URL, path)
        query = params.to_h.compact.to_h.transform_values(&:to_s)
        uri.query = URI.encode_www_form(query) if query.any?
        uri
      rescue URI::InvalidURIError
        raise "Google Calendar request URI is invalid"
      end

      def perform_api_get(uri:, access_token:)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"
        request["Accept"] = "application/json"

        Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google Calendar request failed: #{error.message}"
      end

      def parse_json(raw_body)
        body = raw_body.to_s
        return {} if body.blank?

        JSON.parse(body)
      rescue JSON::ParserError
        {}
      end

      def extract_api_error_message(body)
        body.dig("error", "message").to_s.presence || body["error_description"].to_s.presence || "Unknown API error"
      end

      def refresh_access_token!
        client_id = google_client_id
        client_secret = google_client_secret
        if client_id.blank? || client_secret.blank?
          raise "Google token refresh requires GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET."
        end

        request = Net::HTTP::Post.new(GOOGLE_TOKEN_ENDPOINT)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(
          client_id: client_id,
          client_secret: client_secret,
          refresh_token: connection.refresh_token,
          grant_type: "refresh_token"
        )

        response = Net::HTTP.start(
          GOOGLE_TOKEN_ENDPOINT.host,
          GOOGLE_TOKEN_ENDPOINT.port,
          use_ssl: true,
          open_timeout: REQUEST_OPEN_TIMEOUT_SECONDS,
          read_timeout: REQUEST_TIMEOUT_SECONDS
        ) do |http|
          http.request(request)
        end

        status = response.code.to_i
        body = parse_json(response.body)
        access_token = body["access_token"].to_s.strip

        unless (200..299).cover?(status) && access_token.present?
          message = extract_api_error_message(body)
          raise "Google token refresh failed (#{status}): #{message}"
        end

        persist_refreshed_tokens!(body)
      rescue Timeout::Error, SocketError, Errno::ECONNREFUSED => error
        raise "Google token refresh failed: #{error.message}"
      end

      def persist_refreshed_tokens!(token_body)
        connection.access_token = token_body["access_token"].to_s.strip.presence
        refreshed_token = token_body["refresh_token"].to_s.strip
        connection.refresh_token = refreshed_token if refreshed_token.present?

        scope_values = token_body["scope"].to_s.split(/\s+/).reject(&:blank?)
        connection.scopes_json = scope_values if scope_values.any?

        settings = connection.settings_json.to_h
        if token_body["expires_in"].present?
          expires_at = Time.current + token_body["expires_in"].to_i.seconds
          settings["google_access_token_expires_at"] = expires_at.iso8601
        end
        settings["google_token_type"] = token_body["token_type"].to_s if token_body["token_type"].present?
        connection.settings_json = settings.compact
        connection.save!
      end

      def google_client_id
        connection.settings_json.to_h["google_client_id"].to_s.presence ||
          ENV["GOOGLE_OAUTH_CLIENT_ID"].to_s.presence ||
          ENV["GOOGLE_CLIENT_ID"].to_s.presence
      end

      def google_client_secret
        connection.settings_json.to_h["google_client_secret"].to_s.presence ||
          ENV["GOOGLE_OAUTH_CLIENT_SECRET"].to_s.presence ||
          ENV["GOOGLE_CLIENT_SECRET"].to_s.presence
      end

      def read_only_access_role?(access_role)
        !%w[owner writer].include?(access_role.to_s.downcase)
      end

      def normalize_color_hex(raw_color)
        value = raw_color.to_s.strip
        return DEFAULT_CALENDAR_COLOR if value.blank?

        hex = value.delete_prefix("#")[0, 6]
        return "##{hex.upcase}" if hex.match?(/\A[0-9A-Fa-f]{6}\z/)

        DEFAULT_CALENDAR_COLOR
      end

      def normalize_time_zone_name(raw_time_zone)
        value = raw_time_zone.to_s.strip
        return nil if value.blank?
        return value if ActiveSupport::TimeZone[value].present?

        normalized = value.split("/").last
        return normalized if ActiveSupport::TimeZone[normalized].present?

        nil
      end

      def normalize_status(raw_status)
        value = raw_status.to_s.downcase
        return "cancelled" if value == "cancelled"
        return "tentative" if value == "tentative"

        "confirmed"
      end

      def normalize_visibility(raw_visibility)
        value = raw_visibility.to_s.downcase
        return "public" if value == "public"
        return "private" if value == "private"

        "default"
      end

      def truncate_text(raw_value, limit:, fallback:)
        value = raw_value.to_s.strip
        value = fallback if value.blank?
        value.length > limit ? "#{value[0, limit - 3]}..." : value
      end
    end
  end
end
